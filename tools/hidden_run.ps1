# Lance Godot sans rien afficher (2026-10-22 : essais et captures en
# arriere-plan, « j'ai toujours le petit ecran de chargement Godot ») : sa
# fenetre nait dans une fenetre jamais montree (--wid), ecran de demarrage
# compris ; le rendu et les captures continuent. Passer aussi `-- --offscreen`
# au jeu (son coupe, reglages du joueur jamais reecrits, GameState.go_offscreen).
#
#   HR_EXE=<godot.exe> HR_ARGS='--path game res://dev/net_e2e.tscn -- --offscreen ...' \
#     powershell -NoProfile -ExecutionPolicy Bypass -File tools/hidden_run.ps1
#
# Les arguments passent par HR_ARGS (une chaine) : PowerShell prendrait sinon
# --path, -s ou -- pour les siens. Code de sortie : celui de Godot.
Add-Type -AssemblyName System.Windows.Forms
$host_window = New-Object System.Windows.Forms.Form
$host_window.ShowInTaskbar = $false
$host_window.Width = 1920
$host_window.Height = 1080
$handle = $host_window.Handle.ToInt64()
# le jeu sait ainsi que sa fenetre est deja cachee (rien a deplacer)
$env:CW_HIDDEN_HOST = "1"
$p = Start-Process -FilePath $env:HR_EXE -ArgumentList ("--wid $handle " + $env:HR_ARGS) -NoNewWindow -PassThru -Wait
$host_window.Dispose()
exit $p.ExitCode
