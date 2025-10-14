<?php
declare(strict_types=1);

namespace App\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'app:schema:diff', description: 'Show SQL diff from QR&R (dry-run)')]
class SchemaDiffCommand extends Command
{
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $projectDir = \dirname(__DIR__, 2);
        if (!\defined('sugarEntry')) \define('sugarEntry', true);
        \chdir($projectDir . '/public/legacy');
        require_once 'include/entryPoint.php';
        require_once 'modules/Administration/QuickRepairAndRebuild.php';
        require_once 'modules/Administration/RepairDatabase.php';

        $rc = new \RepairAndClear();
        $rc->repairAndClearAll(['rebuildExtensions','clearVardefs'], [], false, false);

        $rd = new \RepairDatabase();
        $rd->execute = false;
        \ob_start();
        $rd->repairDatabase();
        $sql = \trim((string)\ob_get_clean());

        $output->writeln($sql !== '' ? $sql : '— žádné změny —');
        return Command::SUCCESS;
    }
}
