"""
Organisateur de fichiers universel (O(n)) avec détection de langue locale et gestion de collision intelligente.
"""

import os
import shutil
import locale
from pathlib import Path
from typing import Dict, List, Final
from concurrent.futures import ThreadPoolExecutor

# --- INTERNATIONALISATION ---
def get_i18n_messages() -> Dict[str, str]:
    lang = locale.getdefaultlocale()[0]
    if lang and lang.startswith('fr'):
        return {
            "scan": "🔍 Scan de : {path}",
            "error": "❌ Erreur {file}: {err}",
            "done": "\n✨ Terminé. {count} fichiers rangés.",
            "skipped": "⚠️ Passage : {path} n'existe pas.",
            "moved": "   ✅ [{cat}] {file}"
        }
    return {
        "scan": "🔍 Scanning: {path}",
        "error": "❌ Error {file}: {err}",
        "done": "\n✨ Operation complete. {count} files organized.",
        "skipped": "⚠️ Skipped: {path} does not exist.",
        "moved": "   ✅ [{cat}] {file}"
    }

MSG = get_i18n_messages()

# --- CONFIGURATION (Cross-Platform via Path.home()) ---
SOURCES: Final[List[Path]] = [
    Path.home() / d for d in ["Downloads", "Desktop", "Documents", "Videos", "Music", "Téléchargements", "Bureau", "Vidéos", "Musique"]
]

DESTINATIONS: Final[Dict[str, Path]] = {
    "DOCS": Path.home() / "Documents",
    "IMG": Path.home() / "Pictures",
    "AUDIO": Path.home() / "Music",
    "VIDEO": Path.home() / "Videos",
    "ARCH": Path.home() / "Documents" / "Archives",
    "CODE": Path.home() / "Documents" / "Code",
    "SYS": Path.home() / "Documents" / "ISOs",
    "MISC": Path.home() / "Documents" / "Vrac"
}

EXT_MAP: Final[Dict[str, str]] = {
    # Logic: O(1) lookup
    **{ext: "DOCS" for ext in ('.pdf', '.docx', '.doc', '.txt', '.md', '.odt', '.rtf', '.epub', '.pages')},
    **{ext: "IMG" for ext in ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.tiff', '.svg', '.heic', '.psd', '.ai')},
    **{ext: "AUDIO" for ext in ('.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.mid')},
    **{ext: "VIDEO" for ext in ('.mp4', '.mov', '.mkv', '.avi', '.wmv', '.webm')},
    **{ext: "ARCH" for ext in ('.zip', '.rar', '.7z', '.tar', '.gz', '.xz')},
    **{ext: "CODE" for ext in ('.py', '.js', '.ts', '.sh', '.c', '.cpp', '.h', '.java', '.json', '.yaml', '.rs', '.go')},
    **{ext: "SYS" for ext in ('.exe', '.msi', '.dmg', '.iso', '.pkg', '.deb', '.rpm', '.appimage')}
}

def resolve_path(target: Path) -> Path:
    """Gestion des collisions avec générateur pour éviter la récursion."""
    if not target.exists():
        return target
    stem, suffix = target.stem, target.suffix
    counter = 1
    while (candidate := target.parent / f"{stem}({counter}){suffix}").exists():
        counter += 1
    return candidate

def process_file(item: Path) -> int:
    """Logique atomique pour un fichier unique."""
    if item.is_dir() or item.name.startswith('.') or item.suffix.lower() not in EXT_MAP:
        return 0
    
    cat = EXT_MAP.get(item.suffix.lower(), "MISC")
    target_dir = DESTINATIONS[cat]
    
    if item.parent == target_dir:
        return 0

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        final_path = resolve_path(target_dir / item.name)
        shutil.move(str(item), str(final_path))
        print(MSG["moved"].format(cat=cat, file=item.name))
        return 1
    except (PermissionError, OSError) as e:
        print(MSG["error"].format(file=item.name, err=e))
        return 0

def run():
    total = 0
    # Utilisation d'un set pour éviter les doublons de chemins (Linux/Windows Home mix)
    valid_sources = {s for s in SOURCES if s.exists()}
    
    for source in valid_sources:
        print(MSG["scan"].format(path=source))
        # Parallelisation pour accélérer le scan sur SSD/HDD
        with ThreadPoolExecutor() as executor:
            results = executor.map(process_file, source.iterdir())
            total += sum(results)
            
    print(MSG["done"].format(count=total))

if __name__ == "__main__":
    run()
