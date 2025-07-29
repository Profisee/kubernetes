@echo off
echo ========================================
echo   Profisee Platform Terraform Deployment
echo ========================================
echo.

REM Check if terraform.tfvars exists
if not exist "terraform.tfvars" (
    echo ERROR: terraform.tfvars not found!
    echo.
    echo Please copy sample.tfvars to terraform.tfvars and customize it:
    echo   copy sample.tfvars terraform.tfvars
    echo.
    pause
    exit /b 1
)

echo [INFO] Initializing Terraform...
terraform init
if %ERRORLEVEL% neq 0 (
    echo ERROR: Terraform initialization failed!
    pause
    exit /b 1
)

echo.
echo [INFO] Planning deployment...
terraform plan
if %ERRORLEVEL% neq 0 (
    echo ERROR: Terraform plan failed!
    pause
    exit /b 1
)

echo.
set /p PROCEED="Do you want to proceed with deployment? (y/N): "
if /i not "%PROCEED%"=="y" (
    echo Deployment cancelled.
    pause
    exit /b 0
)

echo.
echo [INFO] Applying Terraform configuration...
terraform apply -auto-approve
if %ERRORLEVEL% neq 0 (
    echo ERROR: Terraform apply failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Deployment Complete!
echo ========================================
echo.
echo View deployment info:
echo   terraform output deployment_summary
echo.
echo Next steps:
echo   terraform output next_steps
echo.
pause
