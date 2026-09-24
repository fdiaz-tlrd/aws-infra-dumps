# aws-infra-dumps

Cuenta AWS activa = el ambiente que estes mirando.

```powershell
cd aws-infra-dumps\scripts
.\dump-por-ambiente.ps1 -Ambiente Sandbox
.\dump-por-ambiente.ps1 -Ambiente QA
.\dump-por-ambiente.ps1 -Ambiente Produccion
```

EFS `/mnt/tld-llaves` de la lambda `tld-alias-cuenta` (Virginia y Oregon):

```powershell
.\dump-efs-llaves.ps1 -Ambiente Sandbox
.\dump-efs-llaves.ps1 -Ambiente QA
.\dump-efs-llaves.ps1 -Ambiente Produccion
```

Solo ver nombres de ALB:

```powershell
.\listar-albs.ps1
```

Salida: `raw/sandbox`, `raw/qa`, `raw/prod` (cada uno con `virginia` y `oregon`).
