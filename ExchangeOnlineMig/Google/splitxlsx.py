import re
from pathlib import Path

import pandas as pd

# ====== CONFIGURACIÓN ======
INPUT_FILE = r"E:\\Work\\Domain\\report.xlsx"
SHEET_NAME = 0
SPLIT_COLUMN = "Recipient"
OUTPUT_DIR = r"E:\\Work\\Domain\\splitreport"
# ===========================

def safe_filename(text: str, max_len: int = 120) -> str:
    """Convierte el valor en un nombre de archivo válido para Windows."""
    text = str(text).strip()
    text = re.sub(r'[<>:"/\\|?*\x00-\x1F]', "_", text)  # inválidos en Windows
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        text = "SIN_VALOR"
    return text[:max_len]

def main():
    input_path = Path(INPUT_FILE)
    out_dir = Path(OUTPUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Lee el Excel
    df = pd.read_excel(input_path, sheet_name=SHEET_NAME)

    if SPLIT_COLUMN not in df.columns:
        raise ValueError(f"La columna '{SPLIT_COLUMN}' no existe. Columnas disponibles: {list(df.columns)}")

    # Para evitar que NaN rompa el agrupado, lo normalizamos
    df[SPLIT_COLUMN] = df[SPLIT_COLUMN].fillna("SIN_VALOR")

    # Agrupa y exporta
    for value, group in df.groupby(SPLIT_COLUMN, dropna=False):
        fname = safe_filename(value)
        output_file = out_dir / f"{fname}.xlsx"

        # Opcional: reordenar por la misma columna u otra si quieres
        # group = group.sort_values(by=[SPLIT_COLUMN])

        # Guarda cada grupo en su propio Excel
        with pd.ExcelWriter(output_file, engine="openpyxl") as writer:
            group.to_excel(writer, index=False, sheet_name="Reporte")

        print(f"Creado: {output_file}")

if __name__ == "__main__":
    main()
