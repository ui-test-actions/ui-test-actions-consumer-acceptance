$ErrorActionPreference = 'Stop'
Start-Process -FilePath $env:POS_EXE -WorkingDirectory (Split-Path -Parent $env:POS_EXE)
