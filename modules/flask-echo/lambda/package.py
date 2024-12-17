import os
import shutil
import zipfile

def create_deployment_package():
    # Get the directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # Create a temporary directory for the package
    if os.path.exists('package'):
        shutil.rmtree('package')
    os.makedirs('package')

    # Copy the main.py file
    shutil.copy2('main.py', 'package/main.py')

    # Create the ZIP file
    with zipfile.ZipFile('function.zip', 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk('package'):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, 'package')
                zipf.write(file_path, arcname)

    # Clean up
    shutil.rmtree('package')

    # Verify the zip file was created
    if not os.path.exists('function.zip'):
        raise RuntimeError("Failed to create function.zip")

if __name__ == '__main__':
    create_deployment_package() 