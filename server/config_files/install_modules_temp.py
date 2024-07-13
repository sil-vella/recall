import subprocess

def install_packages(packages):
    for package in packages:
        subprocess.call(['pip', 'install', package])

if __name__ == "__main__":
    required_packages = [
        "eventlet"
    ]
    
    install_packages(required_packages)