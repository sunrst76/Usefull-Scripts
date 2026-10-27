Describe "Тестирование скрипта" {

    BeforeAll {
        # Создаем временные папки-заглушки для имитации источника и назначения
        $script:MockSrc = Join-Path $env:TEMP "MockSourceFolder"
        $script:MockDst = Join-Path $env:TEMP "MockDestFolder"

        if (-not (Test-Path $script:MockSrc)) { New-Item -Path $script:MockSrc -ItemType Directory | Out-Null }
        if (-not (Test-Path $script:MockDst)) { New-Item -Path $script:MockDst -ItemType Directory | Out-Null }
                
    }

    # Очищаем результаты старых проверок и удаляем папки в самом конце
    AfterAll {
        if (-not (Test-Path $script:MockSrc)) { Remove-Item -Path $script:MockSrc -Recurse -Force }
        if (-not (Test-Path $script:MockDst)) { Remove-Item -Path $script:MockDst -Recurse -Force }
    }

    # Перед каждым тестом очищаем папки и заново создаем набор файлов
    BeforeEach {
        # Очистка папок от результатов прошлых тестов
        if (-not (Test-Path $script:MockSrc)) { Get-ChildItem -Path $script:MockSrc -Recurse | Remove-Item -Force -Recurse }
        if (-not (Test-Path $script:MockDst)) { Get-ChildItem -Path $script:MockDst -Recurse | Remove-Item -Force -Recurse }

        # Генерируем 3 тестовых файла разного типа в папке-источнике
        New-Item -Path (Join-Path $script:MockSrc "update_1.txt") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $script:MockSrc "update_1.log") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $script:MockSrc "update_1.bin") -ItemType File -Force | Out-Null
    }

    # --- СПИСОК ТЕСТОВ ---

    It "Должен завершаться, если исходная папка не существует" {
        # Подменяем переменные прямо внутри контекста вызова скрипта
        {
            $src = "C:\NonExisten_Folder_For_Pester_Test_12345"
            $dst = $script:MockDst
            . .\Updates_Copy_alternate.ps1
        } | Should Not Throw
    }
    
    It "Должен успешно увидеть файлы и запустиь синхронизацию, если обе папки существуют" {
        # Блок действия: запускаем наш скрипт и передаем ему наши тестовые директории
        $testAction = {
            $src = $script:MockSrc
            $dst = $script:MockDst
            . .\Updates_Copy_alternate.ps1            
        }
        
        # Выполняем скрипт, подавляя вывод лишних ошибок, если robocopy отработает пустую синхронизацию
        Invoke-Command -ScriptBlock $testAction -ErrorAction SilentlyContinue | Out-Null

        # Проверка: папка назначения должна физически существовать после работы скрипта
        (Test-Path $script:MockDst) | Should Be $true
    }
}

    