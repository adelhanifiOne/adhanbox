# Script pour lancer l'app AdhanBox
# Usage: .\run_app.ps1 [chrome|android|web]

param(
    [string]$device = "chrome"
)

Write-Host "🚀 Lancement de AdhanBox sur $device..." -ForegroundColor Green

Set-Location $PSScriptRoot

switch ($device.ToLower()) {
    "chrome" {
        Write-Host "📱 Ouverture dans Chrome..." -ForegroundColor Cyan
        flutter run -d chrome
    }
    "web" {
        Write-Host "🌐 Ouverture dans navigateur..." -ForegroundColor Cyan
        flutter run -d web-server
    }
    "android" {
        Write-Host "📱 Lancement émulateur Android..." -ForegroundColor Cyan
        # Démarrer l'émulateur
        Start-Process -NoNewWindow -FilePath "flutter" -ArgumentList "emulators", "--launch", "Pixel_3a_API_30"
        Start-Sleep -Seconds 10
        # Lancer l'app
        flutter run
    }
    "devices" {
        Write-Host "📋 Devices disponibles:" -ForegroundColor Yellow
        flutter devices
    }
    default {
        Write-Host "Usage: .\run_app.ps1 [chrome|android|web|devices]" -ForegroundColor Yellow
        Write-Host "Par défaut: chrome" -ForegroundColor Gray
        flutter run -d chrome
    }
}
