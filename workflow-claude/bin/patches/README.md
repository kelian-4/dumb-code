# Patches de compatibilite C++23/26

Ces deux depots (clones a l'identique depuis GitHub, PAS des forks) utilisent
des fonctionnalites de la stdlib C++23/26 pas encore implementees par la
libstdc++ fournie meme avec gcc-15 (le support syntaxique d'un compilateur
et l'implementation de sa bibliotheque standard sont deux choses
independantes). Ces patchs remplacent chaque appel manquant par un
equivalent manuel. A appliquer avec `git apply <fichier>.patch` a la racine
du depot concerne, juste apres le clone, avant `cmake -B build`.

- `hyprwire-append_range.patch` : `std::vector::append_range` -> boucle
  d'insertion manuelle, sur 6 fichiers (SocketHelpers.cpp,
  HandshakeBegin.cpp, FatalProtocolError.cpp, BindProtocol.cpp,
  HandshakeProtocols.cpp, IWireObject.cpp).
- `hyprland-cpp23-stdlib.patch` : `std::ranges::starts_with` (fonction libre,
  differente de la methode `.starts_with()` deja disponible en C++20 -> pas
  touchee) dans helpers/MiscFunctions.cpp, et `std::string::subview()` dans
  ipc/s1/S1.cpp (remplace par `.substr()`, un log uniquement, aucune
  consequence fonctionnelle).
