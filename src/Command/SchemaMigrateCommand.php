<?php
declare(strict_types=1);

namespace App\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'agme:schema:migrate', description: 'Run Doctrine migrations')]
class SchemaMigrateCommand extends Command
{
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        \passthru('php bin/console doctrine:migrations:migrate -n', $code);
        return $code === 0 ? Command::SUCCESS : Command::FAILURE;
    }
}
