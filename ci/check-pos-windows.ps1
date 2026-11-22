if (Get-Process | Where-Object { $_.MainWindowTitle -match 'Ukkera|POS' }) { exit 0 }
exit 1
