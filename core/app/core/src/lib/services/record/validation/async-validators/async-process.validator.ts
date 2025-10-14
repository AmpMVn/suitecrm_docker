/**
 * SuiteCRM is a customer relationship management program developed by SuiteCRM Ltd.
 * Copyright (C) 2025 SuiteCRM Ltd.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License version 3 as published by the
 * Free Software Foundation with the addition of the following permission added
 * to Section 15 as permitted in Section 7(a): FOR ANY PART OF THE COVERED WORK
 * IN WHICH THE COPYRIGHT IS OWNED BY SUITECRM, SUITECRM DISCLAIMS THE
 * WARRANTY OF NON INFRINGEMENT OF THIRD PARTY RIGHTS.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * In accordance with Section 7(b) of the GNU Affero General Public License
 * version 3, these Appropriate Legal Notices must retain the display of the
 * "Supercharged by SuiteCRM" logo. If the display of the logos is not reasonably
 * feasible for technical reasons, the Appropriate Legal Notices must display
 * the words "Supercharged by SuiteCRM".
 */
import {Injectable} from "@angular/core";
import {Record} from "../../../../common/record/record.model";
import {ViewFieldDefinition} from "../../../../common/metadata/metadata.model";
import {StandardValidationErrors} from "../../../../common/services/validators/validators.model";
import {AbstractControl, AsyncValidatorFn} from "@angular/forms";
import {AsyncProcessValidatorInterface} from "../aync-validator.Interface";
import {Process, ProcessService} from "../../../process/process.service";
import {map, take} from "rxjs/operators";
import {Observable} from "rxjs";
import {AsyncValidationDefinition} from "../../../../common/record/field.model";

export const asyncValidator = (validator: AsyncValidationDefinition, viewField: ViewFieldDefinition, record: Record, processService: ProcessService): AsyncValidatorFn => (
    (control: AbstractControl): Promise<StandardValidationErrors | null> | Observable<StandardValidationErrors | null> => {

        const processKey = validator.key;

        const value = control.value;

        const options = {
            value: value,
            definition: viewField,
            attributes: record.attributes,
            params: validator?.params ?? {}
        };

        return processService.submit(processKey, options).pipe(map((process: Process) => {

            if (process.status !== 'error') {
                return null;
            }

            const error = {
                [processKey]: {
                    message: {
                        labels: {
                            startLabelKey: '',
                            icon: '',
                            endLabelKey: '',
                        },
                        context: {
                            value: control.value
                        }
                    }
                }
            }

            if (process?.data?.errors ?? false){
                Object.keys(process?.data?.errors).forEach((key) => {
                    if (error[processKey].message.labels[key] === ''){
                        error[processKey].message.labels[key] = process?.data?.errors[key];
                    }
                });
            }


            record.fields[viewField.name].asyncValidationErrors = error;

            return error;
        }), take(1));
    }
);

@Injectable({
    providedIn: 'root'
})
export class AsyncProcessValidator implements AsyncProcessValidatorInterface {

    constructor(
        protected processService: ProcessService
    ) {
    }

    applies(record: Record, viewField: ViewFieldDefinition): boolean {
        return !(!viewField || !viewField.fieldDefinition);
    }

    getValidator(validator: AsyncValidationDefinition, viewField: ViewFieldDefinition, record: Record): AsyncValidatorFn {
        if (!viewField || !viewField.fieldDefinition) {
            return null;
        }

        if (!validator?.key){
            return null;
        }

        return asyncValidator(validator, viewField, record, this.processService);
    }
}
