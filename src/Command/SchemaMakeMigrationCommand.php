<?php
declare(strict_types=1);

namespace App\Command;

use DateTimeImmutable;
use DateTimeZone;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'agme:schema:make-migration', description: 'Generate Doctrine migration from SuiteCRM QR&R diff')]
class SchemaMakeMigrationCommand extends Command
{
    protected function configure(): void
    {
        $this->addArgument('description', InputArgument::OPTIONAL, 'Short description', 'Schema update');
    }

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

        $statements = \preg_split('/;\s*\R/s', \str_replace("\r", '', $sql));
        $ddl = \array_values(\array_filter(\array_map('trim', $statements), fn($s) =>
            $s !== '' && !\preg_match('/^(SELECT\s|\/\*|--)/i', $s)
        ));

        if (!$ddl) {
            $output->writeln('<info>Žádné schémové změny – migrace není potřeba.</info>');
            return Command::SUCCESS;
        }

        $ts = (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('YmdHis');
        $class = "Version{$ts}";
        $migrationsDir = $projectDir . '/migrations';
        if (!\is_dir($migrationsDir)) \mkdir($migrationsDir, 0o777, True);
        $desc  = \addslashes((string)$input->getArgument('description'));

        $body = '';
        foreach ($ddl as $sqlStmt) {
            $s = \ltrim($sqlStmt);
            if (\preg_match('/^CREATE\s+TABLE\s+`?(\w+)`?/i', $s, $m)) {
                $t = $m[1];
                $body .= <<<PHP
        // create table if not exists
        if (!\$this->connection->createSchemaManager()->tablesExist(['{$t}'])) {
            \$this->addSql("{$sqlStmt}");
        }

PHP;
                continue;
            }
            if (\preg_match('/^CREATE\s+(UNIQUE\s+)?INDEX\s+`?(\w+)`?\s+ON\s+`?(\w+)`?/i', $s, $m)) {
                $idx = $m[2]; $tbl = $m[3];
                $body .= <<<PHP
        // create index if missing
        \$sm = \$this->connection->createSchemaManager();
        if (!\$sm->introspectTable('{$tbl}')->hasIndex('{$idx}')) {
            \$this->addSql("{$sqlStmt}");
        }

PHP;
                continue;
            }
            if (\preg_match('/^ALTER\s+TABLE\s+`?(\w+)`?\s+ADD\s+`?(\w+)`?/i', $s, $m)) {
                $tbl = $m[1]; $col = $m[2];
                $body .= <<<PHP
        // add column if missing
        \$sm = \$this->connection->createSchemaManager();
        \$cols = array_map(fn(\$c)=>\$c->getName(), \$sm->introspectTable('{$tbl}')->getColumns());
        if (!in_array('{$col}', \$cols, true)) {
            \$this->addSql("{$sqlStmt}");
        }

PHP;
                continue;
            }
            $body .= "        \$this->addSql(\"{$sqlStmt}\");\n\n";
        }

        $tpl = <<<PHP
<?php
declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\\DBAL\\Schema\\Schema;
use Doctrine\\Migrations\\AbstractMigration;

final class {$class} extends AbstractMigration
{
    public function getDescription(): string
    {
        return '{$desc}';
    }

    public function up(Schema \$schema): void
    {
{$body}    }

    public function down(Schema \$schema): void
    {
        // TODO: doplň případný rollback
    }
}

PHP;

        \file_put_contents($migrationsDir . "/{$class}.php", $tpl);
        $output->writeln("<info>Vytvořena migrace:</info> migrations/{$class}.php");
        return Command::SUCCESS;
    }
}
