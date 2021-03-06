@echo off
SETLOCAL EnableDelayedExpansion
:: usage: matlab_wrapper.bat <params_path> <worker-id> <matlab-pid
:: main loop:
:: - check in redis to see status
:: - if matlab is said to be killed, kill it
::      - search current task (if exists) and move to failed with errormsg of matlab died
:: - if matlab is said to be alive but isn't:
::      - search current task (if exists) and move to failed with errormsg of matlab died
::      - if matlab_restart_on_fail restart matlab with the same worker-id?
set params_path=%1
set worker_key=%2
set matlab_pid=%3
set start_matlab_worker_path=%~dp0%start_matlab_worker.bat
set DB_ID=INITIAL_DB_ID

for /f "usebackq" %%i IN (`hostname`) DO SET hostname=%%i

call :logger INFO load parameters from %params_path%
for /f "tokens=1,* delims==" %%x in ('type "%params_path%"') do call :run_and_set %%x %%y

call :logger INFO check that redis exists 
if not exist %redis_cli_path% (echo !redis_cli_path! does not exists & exit /b) 

call :send_redis ping
if "%res%"=="failed" (
    call :logger ERROR failed pinging redis %redis_cli_path% -h %redis_hostname% -p %redis_port% -a %redis_password% -n %redis_db%
    exit /b
) else (
    call :logger INFO redis ping ponged
) 


:main_loop
    @timeout %wrapper_loop_wait_seconds% >nul

    :: check if matlab is alive
    call :is_pid_alive !matlab_pid!
    set matlab_status=!res!

    :: check redis status
    call :redis_check_id
    call :send_redis hget !worker_key! status
    if "!res!"=="failed" (
        call :logger WARNING redis failed with command !redis_cmd! hget !worker_key! status
        goto main_loop
    )
    set worker_status=!res!

    call :logger VERBOSE matlab_status:!matlab_status! redis_status:!worker_status!

    :: main logic
    if "!matlab_status!"=="off" (     
        call :logger INFO matlab died    
        call :move_current_task_to_failed !worker_key! "worker died"
        call :send_redis hset !worker_key! status dead
        if "%matlab_restart_on_fail%"=="true" (
            call %start_matlab_worker_path%
        )
        exit /s
    )

    if "!worker_status!"=="restart" (        
        call :kill_wait_and_deal_with_current_task !worker_key! !matlab_pid!
        call :logger INFO worker restart
        call %start_matlab_worker_path%
        exit /s
    )

    if "!worker_status!"=="kill" (
        call :kill_wait_and_deal_with_current_task !worker_key! !matlab_pid!
        exit /s
    )

goto main_loop

:: =================== helper functions ========================
:logger
for /f "tokens=1,* delims= " %%a in ("%*") do set ALL_BUT_FIRST=%%b
echo [%1] %date%T%time% %ALL_BUT_FIRST%
exit /b

:redis_check_id
call :send_redis get db_id
if "!res!"=="failed" (
    call :logger WARNING db-id was not found or redis timeout, wait and retry
    @timeout %wrapper_loop_wait_seconds% >nul
    goto redis_check_id
) else (
    if "!DB_ID!"=="INITIAL_DB_ID" (
        set DB_ID=!res!
    )
    if not "!DB_ID!"=="!res!" (
        call :logger WARNING expect db-id !DB_ID! got !res! restart worker
        taskkill /PID !matlab_pid!
        call :logger INFO worker restart
        call %start_matlab_worker_path%
        exit /s
    )
)
exit /b

:kill_wait_and_deal_with_current_task
call :logger INFO kill matlab worker %1 of pid=%2
taskkill /F /PID %2

:wait_check_pid_alive
call :logger DEBUG still alive pid=%2
call :is_pid_alive %2
if !res!==on (goto wait_check_pid_alive)
call :logger DEBUG process dead check move task to failed    
call :move_current_task_to_failed %1 "worker killed"        
call :send_redis hset %1 status dead

exit /b

:datestr
set day-num=%date:~0,2%
set year-num=%date:~6,4%
set month-num=%date:~3,2%
if %month-num%==01 set mo-name=Jan
if %month-num%==02 set mo-name=Feb
if %month-num%==03 set mo-name=Mar
if %month-num%==04 set mo-name=Apr
if %month-num%==05 set mo-name=May
if %month-num%==06 set mo-name=Jun
if %month-num%==07 set mo-name=Jul
if %month-num%==08 set mo-name=Aug
if %month-num%==09 set mo-name=Sep
if %month-num%==10 set mo-name=Oct
if %month-num%==11 set mo-name=Nov
if %month-num%==12 set mo-name=Dec
set res=%day-num%-%mo-name%-%year-num% %time%
exit /b

:move_current_task_to_failed 
call :redis_check_id
call :send_redis hget %1 current_task
if not "!res!"=="failed" if not "!res!"=="None" (       
    set current_task=!res!
    :: move task from ongoing to error and push error message
    call :datestr
    call :send_redis hset !current_task! failed_on "!res!"
    call :send_redis hset !current_task! status failed
    call :send_redis hset !current_task! err_msg %2
    call :send_redis lrem ongoing_tasks 0 !current_task!
    call :send_redis lpush failed_tasks !current_task!
    call :send_redis hset %1 current_task None
)
exit /b

:get_parent_pid
for /f "usebackq tokens=2 delims==" %%a in (`wmic process where ^(processid^=%1^) get parentprocessid /value`) do (
    set res=%%a
)
exit /b

:get_pid_by_window_name
for /f "tokens=2 USEBACKQ" %%f IN (`tasklist /NH /FI "WINDOWTITLE eq %1"`) do (set "res=%%f")
exit /b

:get_pid
@REM for /f "tokens=2 USEBACKQ" %%f IN (`tasklist /NH /FI "WINDOWTITLE eq *%1"`) do (set "res=%%f")
for /f "tokens=2 USEBACKQ" %%f IN (`tasklist /nh /v /fi "IMAGENAME eq matlab.exe" ^| find "%1"`) do (set "res=%%f")
@REM echo pid of %1 is %res%
exit /b

:is_pid_alive
set res=off
for /f "tokens=2 USEBACKQ" %%f IN (`tasklist /nh /fi "pid eq %1"`) do (
    if "%%f"=="%1" (
        set "res=on"
    ) else (
        set "res=off"
    )
)
exit /b

:start_matlab
@REM echo start matlab process at %matlab_path%
start "%1" "%matlab_path%" -sd "%~dp0" -batch "%matlab_runner_script%"
call :get_pid %1
exit /b

:kill
taskkill /f /t /fi "windowtitle eq %1"
exit /b

:run_and_set
for /f "tokens=1,* delims= " %%a in ("%*") do set %1=%%b
exit /b

:send_redis
set res=failed
set "redis_cmd=%redis_cli_path% -h %redis_hostname% -p %redis_port% -a %redis_password% -n %redis_db%"
for /f "tokens=*" %%g in ('!redis_cmd! %*') do (set res=%%g)
exit /b

