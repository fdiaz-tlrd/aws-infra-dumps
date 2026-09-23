# aws-infra-dumps

Scripts AWS CLI (`.ps1`) + salidas JSON/CSV para estudiar infra (ALB, custom domains, etc.)
sin copiar/pegar por RDP.

- **Cuenta GitHub:** [fdiaz-tlrd](https://github.com/fdiaz-tlrd?tab=repositories)
- **Estudio / narrativa:** repo hermano `second-brain` (`alb/`)
- **Este repo:** solo scripts + raw dumps

## En el servidor RDP (con AWS CLI)

```powershell
git clone https://github.com/fdiaz-tlrd/aws-infra-dumps.git
cd aws-infra-dumps\scripts\sandbox-oregon

.\dump-alb-sandbox-oregon.ps1
.\revisar-dominios-personalizados.ps1

cd ..\..
git add raw
git commit -m "dump sandbox oregon"
git push
```

En la Lenovo: `git pull` y analizar (Cursor lee `raw/`).

## Layout

```
scripts/sandbox-oregon/   # .ps1
raw/sandbox-oregon/alb/   # salida dump ALB
raw/sandbox-oregon/dominios/  # salida dominios APIGW
```

Mas ambientes/regiones: `scripts/<celda>/` y `raw/<celda>/` (ej. `prod-virginia`).
