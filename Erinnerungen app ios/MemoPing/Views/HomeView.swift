# 1. Richtige Repo klonen (neuen Token verwenden!)
cd C:\Users\jansz
git clone https://janszala619-create:NEUER_TOKEN@github.com/janszala619-create/app.git
cd app

# 2. ZIP entpacken und Dateien ersetzen
Expand-Archive -Path "C:\Users\jansz\Downloads\app_komplett.zip" -DestinationPath "C:\Users\jansz\Downloads\app_fix" -Force

$src = "C:\Users\jansz\Downloads\app_fix\app-main\Erinnerungen app ios\MemoPing"
$dest = "C:\Users\jansz\app\Erinnerungen app ios\MemoPing"

Copy-Item "$src\Views\HomeView.swift" "$dest\Views\HomeView.swift" -Force
Copy-Item "$src\Views\CaptureView.swift" "$dest\Views\CaptureView.swift" -Force
Copy-Item "$src\Views\DetailView.swift" "$dest\Views\DetailView.swift" -Force
Copy-Item "$src\Components\MemoCardView.swift" "$dest\Components\MemoCardView.swift" -Force

# 3. Pushen
git add .
git commit -m "Fix: HomeView, CaptureView, DetailView, MemoCardView verbessert"
git push
