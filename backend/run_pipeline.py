import subprocess

steps = [
    "pipeline/01_collection.py",
    "pipeline/02_staging.py",
    "pipeline/03_cleansing.py",
    "pipeline/04_transformation.py",
    "pipeline/05_presentation.py",
    "pipeline/06_prediction.py"
]

for step in steps:
    print(f"\nRunning {step} ...")
    subprocess.run(["python", step])

print("\nPipeline Automation Completed Successfully!")
