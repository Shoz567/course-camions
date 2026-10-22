# Lance Godot en arriere-plan (2026-10-22 : essais et captures sans gener le
# joueur, « j'ai toujours le petit ecran de chargement Godot » ; « je veux
# quand meme pouvoir y acceder ») : sa fenetre nait dans une fenetre hote
# reduite, sans etre activee - rien ne s'affiche, ecran de demarrage compris,
# mais l'essai est dans la barre des taches (« Crazy Wheels - essai de
# Claude ») : un clic l'ouvre, le fermer arrete Godot. Le rendu et les
# captures continuent. Passer aussi `-- --offscreen` au jeu (reglages du
# joueur jamais reecrits, GameState.go_offscreen), et `--mute` pour le
# silence.
#
#   HR_EXE=<godot.exe> HR_ARGS='--path game res://dev/net_e2e.tscn -- --offscreen ...' \
#     powershell -NoProfile -ExecutionPolicy Bypass -File tools/hidden_run.ps1
#
# Les arguments passent par HR_ARGS (une chaine) : PowerShell prendrait sinon
# --path, -s ou -- pour les siens. Code de sortie : celui de Godot.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Win32 -Name Window -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
"@
$host_window = New-Object System.Windows.Forms.Form
$host_window.Text = "Crazy Wheels - essai de Claude"
$host_window.ShowInTaskbar = $true
$host_window.ClientSize = New-Object System.Drawing.Size(1920, 1080)
$host_window.StartPosition = "CenterScreen"
$host_window.BackColor = [System.Drawing.Color]::Black
$handle = $host_window.Handle
$script:closed = $false
$host_window.Add_FormClosed({ $script:closed = $true })
# SW_SHOWMINNOACTIVE : dans la barre des taches, reduite, sans prendre le focus
[Win32.Window]::ShowWindow($handle, 7) | Out-Null
# le jeu sait ainsi que sa fenetre est deja hebergee (rien a deplacer)
$env:CW_HIDDEN_HOST = "1"
$p = Start-Process -FilePath $env:HR_EXE -ArgumentList ("--wid " + $handle.ToInt64() + " " + $env:HR_ARGS) -NoNewWindow -PassThru
# boucle de messages : la fenetre hote repond aux clics (ouvrir, reduire, fermer)
while (-not $p.HasExited) {
	[System.Windows.Forms.Application]::DoEvents()
	if ($script:closed -or $host_window.IsDisposed) {
		Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
		break
	}
	Start-Sleep -Milliseconds 30
}
$p.WaitForExit()
if (-not $host_window.IsDisposed) {
	$host_window.Dispose()
}
exit $p.ExitCode
