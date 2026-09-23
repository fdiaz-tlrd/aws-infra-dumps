# aws-infra-dumps

Scripts AWS CLI (`.ps1`) + salidas JSON/CSV.
Flujo: clonar en RDP -> ejecutar -> `git push` -> en Lenovo `git pull`.

- GitHub: https://github.com/fdiaz-tlrd/aws-infra-dumps
- Estudio: `second-brain` (`alb/`)

## RDP (sandbox, Virginia + Oregon)

```powershell
git clone https://github.com/fdiaz-tlrd/aws-infra-dumps.git
cd aws-infra-dumps
git pull

cd scripts
.\dump-alb.ps1
.\revisar-dominios-personalizados.ps1

cd ..
git add raw/sandbox
git commit -m "dump sandbox virginia+oregon"
git push
```

Solo una region:

```powershell
.\dump-alb.ps1 -Regions us-east-1
.\revisar-dominios-personalizados.ps1 -Regions us-west-2
```

## Layout

```
scripts/
  dump-alb.ps1
  revisar-dominios-personalizados.ps1
raw/sandbox/
  virginia/   # us-east-1
    alb/<nombre-alb>/
    dominios/
  oregon/     # us-west-2
    alb/<nombre-alb>/
    dominios/
```

`dump-alb.ps1` busca ALBs cuyo nombre coincida con `*sandbox*` (param `-NameFilter`).
Los target groups se leen del ALB (no hay nombre fijo).
