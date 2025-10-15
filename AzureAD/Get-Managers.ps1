Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"

$usuarios = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,GivenName,Surname,Mail,Department,JobTitle

$listado = @()

$usuarios |  ForEach-Object { 
		$usuario = $_; 
		$mgr = Get-MgUserManager -UserId $usuario.Id -ErrorAction SilentlyContinue; 
		if ($mgr) {
			$umgr = Get-MgUser -UserId $mgr.Id; 
			$listado += [pscustomobject]@{
				NombreEmpleado = $usuario.DisplayName
				Nombre = $usuario.GivenName
				Apellido = $usuario.Surname
				Email = $usuario.Mail
				Departamento = $usuario.Department
				Cargo = $usuario.JobTitle
				NombreManager = $umgr.DisplayName
			}
		}
		else {
			$listado += [pscustomobject]@{
				NombreEmpleado = $usuario.DisplayName
				Nombre = $usuario.GivenName
				Apellido = $usuario.Surname
				Email = $usuario.Mail
				Departamento = $usuario.Department
				Cargo = $usuario.JobTitle
				NombreManager = ""
			}
		}
	}

# En PowerShell 5:
$listado | Export-Csv -Path C:\temp\listadomanagers.csv -Delimiter ";"

# En powerShel 7:
# $listado | Export-Csv -Path C:\temp\listadomanagers.csv -Delimiter ";" -Encoding UTF8BOM
