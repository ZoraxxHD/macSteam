// Bilingual localization system (Français & English) with auto-detection and live switching.
import Foundation

enum L10n {
    static let languageChangedNotification = Notification.Name("MacsteamLanguageChanged")

    enum Language: String, CaseIterable {
        case system = "system"
        case fr = "fr"
        case en = "en"

        var displayName: String {
            switch self {
            case .system: return L10n.tr("settings.lang.system")
            case .fr:     return "Français"
            case .en:     return "English"
            }
        }
    }

    static var currentLanguageSetting: Language {
        get {
            let raw = AppSettings.shared.language ?? "system"
            return Language(rawValue: raw) ?? .system
        }
        set {
            AppSettings.shared.language = (newValue == .system) ? nil : newValue.rawValue
            NotificationCenter.default.post(name: languageChangedNotification, object: nil)
        }
    }

    static var effectiveLanguage: String {
        let setting = currentLanguageSetting
        if setting != .system { return setting.rawValue }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("fr") { return "fr" }
        return "en"
    }

    static var isFrench: Bool { effectiveLanguage == "fr" }

    static func tr(_ key: String) -> String {
        let lang = effectiveLanguage
        if lang == "fr", let val = frStrings[key] { return val }
        return enStrings[key] ?? key
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, arguments: args)
    }

    // MARK: - French Dictionary

    private static let frStrings: [String: String] = [
        // Sidebar groups & items
        "sidebar.group.discover": "Découvrir & Ajouter",
        "sidebar.home": "Tableau de bord",
        "sidebar.search": "Rechercher & Ajouter",
        "sidebar.import": "Importer Zip / Lua",
        "sidebar.group.library": "Bibliothèque",
        "sidebar.apps": "Mes Jeux",
        "sidebar.builds": "Dépôts & Builds",
        "sidebar.fixes": "Correctifs (Fixes)",
        "sidebar.downloads": "Téléchargements",
        "sidebar.group.macsteam": "macSteam",
        "sidebar.plugin": "Plugin Boutique Steam",
        "sidebar.install": "Installation macSteam",
        "sidebar.crossover": "CrossOver Steam",
        "sidebar.cloud_redirect": "CloudRedirect",
        "sidebar.repair": "Réparer Steam",
        "sidebar.settings": "Réglages",

        // Home Dashboard
        "home.title": "Tableau de bord",
        "home.subtitle": "Gérez vos jeux déverrouillés, vos sources de manifests et l'intégration native macSteam.",
        "home.card.games": "Jeux déverrouillés",
        "home.card.games.sub": "%d jeu(x) · %d DLC configuré(s)",
        "home.card.macsteam": "État de macSteam",
        "home.card.steam": "Client Steam macOS",
        "home.card.steam.found": "Détecté dans /Applications/Steam.app",
        "home.card.steam.missing": "Steam.app introuvable dans /Applications",
        "home.card.account": "Compte LuaTools & Hubcap",
        "home.card.account.guest": "Navigation en invité",
        "home.card.account.signedin": "Connecté : %@",
        "home.card.account.hubcap": "Clé API Hubcap active",
        "home.card.plugin": "Plugin Boutique Steam (CEF)",
        "home.card.plugin.active": "Actif (Port 6767 · Pont CEF 8080)",
        "home.card.plugin.inactive": "Non installé dans Steam",
        "home.recent.title": "Récemment ajoutés",
        "home.recent.empty": "Aucun jeu déverrouillé pour le moment. Utilisez « Rechercher & Ajouter » ou glissez un fichier .zip/.lua.",
        "home.quick.search": "Rechercher un jeu",
        "home.quick.import": "Importer Zip / Lua…",
        "home.quick.restart_steam": "Redémarrer Steam",
        "home.quick.open_steam": "Ouvrir Steam",

        // Search & Download (Add Games)
        "search.title": "Rechercher & Ajouter",
        "search.placeholder": "Rechercher un jeu Steam, un AppID ou coller un lien store.steampowered.com…",
        "search.fastfetch": "FastFetch (Téléchargement auto)",
        "search.featured.top": "Meilleures ventes Steam",
        "search.featured.new": "Nouveautés Steam",
        "search.btn.check_sources": "Vérifier les sources",
        "search.btn.check_dlc": "Vérifier les dépôts DLC",
        "search.btn.generate_dlc": "Générer et installer le DLC",
        "search.sources.title": "Sources de manifests disponibles",
        "search.sources.checking": "Vérification de la disponibilité des sources…",
        "search.sources.empty": "Aucune source trouvée pour cet AppID.",
        "search.status.available": "DISPONIBLE",
        "search.status.unavailable": "INDISPONIBLE",
        "search.status.needs_key": "CLÉ HUBCAP REQUISE",
        "search.btn.download": "Télécharger & Installer",
        "search.btn.downloading": "En cours…",
        "search.dlc.badge": "DLC · Jeu de base : %@",
        "search.game.badge": "Jeu complet · AppID %d",
        "search.installed.banner": "Installé avec succès : %@",
        "search.btn.reveal_library": "Voir dans Mes Jeux",
        "search.err.signin_required": "Connexion LuaTools ou clé API Hubcap requise pour télécharger depuis cette source.",
        "search.overwrite.title": "Remplacer la configuration de %@ ?",
        "search.overwrite.subtitle": "Ce jeu est déjà configuré dans macSteam. Voici les différences :",
        "search.overwrite.added": "Ajouté(s) (%d) : %@",
        "search.overwrite.removed": "Retiré(s) (%d) : %@",
        "search.overwrite.no_changes": "Aucun changement de dépôt ou DLC détecté (mise à jour des manifests).",
        "search.overwrite.confirm": "Remplacer & Mettre à jour",

        // Library / Apps
        "library.title": "Mes Jeux",
        "library.search.placeholder": "Filtrer par nom ou AppID…",
        "library.filter.all_types": "Tous types",
        "library.filter.games": "Jeux",
        "library.filter.dlc": "DLC",
        "library.filter.all_prices": "Tous prix",
        "library.filter.free": "Gratuit",
        "library.filter.paid": "Payant",
        "library.sort.recent": "Tri : Ajout récent",
        "library.sort.name": "Tri : Nom (A–Z)",
        "library.sort.metacritic": "Tri : Metacritic",
        "library.inspector.empty": "Sélectionnez un jeu pour afficher ses détails, ses DLC et ses options.",
        "library.inspector.update": "Mettre à jour (Sources)",
        "library.inspector.depots": "Dépôts & Builds",
        "library.inspector.launch_options": "Options de lancement…",
        "library.inspector.open_steam": "Ouvrir dans Steam",
        "library.inspector.store_page": "Page Boutique Steam",
        "library.inspector.reveal_finder": "Révéler dans le Finder",
        "library.inspector.copy_appid": "Copier l'AppID",
        "library.inspector.remove": "Retirer de macSteam",
        "library.launch_options.title": "Options de lancement Steam — %@",
        "library.launch_options.info": "Arguments passés au jeu par Steam au lancement (stockés dans localconfig.vdf). Exemple : -windowed, variables Wine/CrossOver/GPTK.",
        "library.launch_options.save": "Enregistrer",

        // Depots & Builds
        "builds.title": "Dépôts & Builds",
        "builds.games.placeholder": "Filtrer les jeux…",
        "builds.variants.title": "Versions / Presets Lua enregistrés",
        "builds.btn.apply": "Appliquer la version",
        "builds.btn.save_preset": "Sauvegarder en preset…",
        "builds.btn.edit_lua": "Éditer le Lua…",
        "builds.btn.rename": "Renommer…",
        "builds.btn.delete_variant": "Supprimer la version",
        "builds.depots.title": "Dépôts & DLC déclarés",
        "builds.depots.search": "Filtrer les dépôts, DLC ou GID de manifest…",
        "builds.depot.enabled": "Actif",
        "builds.depot.pinned": "Épinglé",
        "builds.depot.download_manifest": "Télécharger .manifest",
        "builds.empty": "Sélectionnez un jeu à gauche pour gérer ses dépôts, clés de déchiffrement et builds.",

        // Fixes
        "fixes.title": "Correctifs (Fixes)",
        "fixes.search.placeholder": "Rechercher un jeu avec correctif…",
        "fixes.filter.my_games": "Mes jeux uniquement",
        "fixes.filter.all_tags": "Tous les tags",
        "fixes.btn.refresh": "Actualiser",
        "fixes.empty": "Aucun correctif trouvé.",
        "fixes.detail.empty": "Sélectionnez un jeu pour voir les correctifs disponibles.",
        "fixes.btn.download_manifest": "Installer Manifest (Épinglé)",
        "fixes.btn.apply_fix": "Appliquer le Fix dans le dossier du jeu",
        "fixes.btn.revert_fix": "Restaurer les fichiers originaux",
        "fixes.status.applied": "Correctif appliqué",
        "fixes.status.game_not_installed": "Jeu non installé localement dans Steam",

        // Downloads Queue
        "downloads.title": "Téléchargements",
        "downloads.active.title": "En cours & File d'attente",
        "downloads.history.title": "Historique des téléchargements",
        "downloads.btn.clear_history": "Effacer l'historique",
        "downloads.btn.cancel": "Annuler",
        "downloads.btn.retry": "Réessayer",
        "downloads.empty": "Aucun téléchargement actif ou dans l'historique.",

        // Store Plugin
        "plugin.title": "Plugin Boutique Steam",
        "plugin.subtitle": "Injecte le bouton « Add via LuaTools / macSteam » directement sur les pages de la boutique dans le client Steam macOS via le pont CEF.",
        "plugin.status.installed": "Plugin actif et prêt",
        "plugin.status.not_installed": "Plugin non configuré",
        "plugin.row.server": "Serveur local HTTP (127.0.0.1:6767)",
        "plugin.row.cef": "Débogage distant CEF Steam (.cef-enable-remote-debugging · Port 8080)",
        "plugin.row.script": "Script Frontend (luatools.js)",
        "plugin.btn.install": "Installer / Activer le Plugin",
        "plugin.btn.update": "Mettre à jour depuis GitHub",
        "plugin.btn.uninstall": "Désinstaller le Plugin",
        "plugin.btn.restart_steam": "Redémarrer Steam pour appliquer",

        // Settings
        "settings.title": "Réglages",
        "settings.group.general": "Général & Interface",
        "settings.lang.title": "Langue de l'application",
        "settings.lang.system": "Automatique (Système macOS)",
        "settings.hide_whats_new": "Masquer l'étagère « Quoi de neuf » dans Steam",
        "settings.fast_fetch": "FastFetch (télécharger automatiquement depuis la meilleure source)",
        "settings.auto_update_apps": "Mise à jour auto des jeux (ne pas épingler les manifests par défaut)",
        "settings.donate_keys": "Partager automatiquement les nouvelles clés de dépôt avec la communauté",
        "settings.cef_plugin": "Activer le serveur local et l'injection CEF pour la boutique Steam",
        "settings.group.account": "Compte LuaTools (lua.tools)",
        "settings.account.guest": "Non connecté (Mode invité)",
        "settings.account.signin_discord": "Se connecter avec Discord…",
        "settings.account.signin_code": "Utiliser un code Bot (6 car.)",
        "settings.account.signout": "Se déconnecter",
        "settings.account.code_placeholder": "Code /login",
        "settings.group.hubcap": "Clé API Hubcap (hubcapmanifest.com)",
        "settings.hubcap.placeholder": "Collez votre clé smm_…",
        "settings.hubcap.save": "Valider & Enregistrer",
        "settings.hubcap.clear": "Effacer la clé",
        "settings.hubcap.refresh": "Actualiser le quota",
        "settings.hubcap.configured": "Clé configurée · Quota aujourd'hui : %d / %d requêtes",
        "settings.group.updates": "Mises à jour",
        "settings.updates.auto": "Vérifier automatiquement les mises à jour",
        "settings.updates.check": "Rechercher des mises à jour…",

        // Common
        "common.error": "Erreur",
        "common.cancel": "Annuler",
        "common.save": "Enregistrer",
        "common.remove": "Retirer",
        "common.ok": "OK",
        "common.loading": "Chargement…",
    ]

    // MARK: - English Dictionary

    private static let enStrings: [String: String] = [
        // Sidebar groups & items
        "sidebar.group.discover": "Discover & Add",
        "sidebar.home": "Home Dashboard",
        "sidebar.search": "Search & Add Games",
        "sidebar.import": "Import Zip / Lua",
        "sidebar.group.library": "Library",
        "sidebar.apps": "My Games",
        "sidebar.builds": "Depots & Builds",
        "sidebar.fixes": "Game Fixes",
        "sidebar.downloads": "Downloads",
        "sidebar.group.macsteam": "macSteam",
        "sidebar.plugin": "Steam Store Plugin",
        "sidebar.install": "Install macSteam",
        "sidebar.crossover": "CrossOver Steam",
        "sidebar.cloud_redirect": "CloudRedirect",
        "sidebar.repair": "Repair Steam",
        "sidebar.settings": "Settings",

        // Home Dashboard
        "home.title": "Home Dashboard",
        "home.subtitle": "Manage your unlocked games, manifest sources, and native macSteam integration.",
        "home.card.games": "Unlocked Games",
        "home.card.games.sub": "%d game(s) · %d DLC configured",
        "home.card.macsteam": "macSteam Status",
        "home.card.steam": "macOS Steam Client",
        "home.card.steam.found": "Detected at /Applications/Steam.app",
        "home.card.steam.missing": "Steam.app not found in /Applications",
        "home.card.account": "LuaTools & Hubcap Account",
        "home.card.account.guest": "Browsing as Guest",
        "home.card.account.signedin": "Signed in: %@",
        "home.card.account.hubcap": "Hubcap API Key active",
        "home.card.plugin": "Steam Store Plugin (CEF)",
        "home.card.plugin.active": "Active (Port 6767 · CEF Bridge 8080)",
        "home.card.plugin.inactive": "Not enabled in Steam",
        "home.recent.title": "Recently Added",
        "home.recent.empty": "No games unlocked yet. Use 'Search & Add Games' or drop a .zip/.lua file.",
        "home.quick.search": "Search Games",
        "home.quick.import": "Import Zip / Lua…",
        "home.quick.restart_steam": "Restart Steam",
        "home.quick.open_steam": "Open Steam",

        // Search & Download (Add Games)
        "search.title": "Search & Add Games",
        "search.placeholder": "Search a Steam game, AppID, or paste a store.steampowered.com link…",
        "search.fastfetch": "FastFetch (Auto-download)",
        "search.featured.top": "Steam Top Sellers",
        "search.featured.new": "Steam New Releases",
        "search.btn.check_sources": "Check Sources",
        "search.btn.check_dlc": "Check DLC Depots",
        "search.btn.generate_dlc": "Generate & Install DLC",
        "search.sources.title": "Available Manifest Sources",
        "search.sources.checking": "Checking source availability…",
        "search.sources.empty": "No manifest sources found for this AppID.",
        "search.status.available": "AVAILABLE",
        "search.status.unavailable": "UNAVAILABLE",
        "search.status.needs_key": "NEEDS HUBCAP KEY",
        "search.btn.download": "Download & Install",
        "search.btn.downloading": "Working…",
        "search.dlc.badge": "DLC · Base Game: %@",
        "search.game.badge": "Full Game · AppID %d",
        "search.installed.banner": "Successfully installed: %@",
        "search.btn.reveal_library": "Show in My Games",
        "search.err.signin_required": "LuaTools sign-in or a Hubcap API key is required to download from this source.",
        "search.overwrite.title": "Replace configuration for %@?",
        "search.overwrite.subtitle": "This game is already configured in macSteam. Here are the changes:",
        "search.overwrite.added": "Added (%d): %@",
        "search.overwrite.removed": "Removed (%d): %@",
        "search.overwrite.no_changes": "No depot or DLC changes detected (manifest update only).",
        "search.overwrite.confirm": "Replace & Update",

        // Library / Apps
        "library.title": "My Games",
        "library.search.placeholder": "Filter by name or AppID…",
        "library.filter.all_types": "All Types",
        "library.filter.games": "Games",
        "library.filter.dlc": "DLC",
        "library.filter.all_prices": "All Prices",
        "library.filter.free": "Free",
        "library.filter.paid": "Paid",
        "library.sort.recent": "Sort: Recently Added",
        "library.sort.name": "Sort: Name (A–Z)",
        "library.sort.metacritic": "Sort: Metacritic",
        "library.inspector.empty": "Select a game to view its details, DLCs, and actions.",
        "library.inspector.update": "Update (Sources)",
        "library.inspector.depots": "Depots & Builds",
        "library.inspector.launch_options": "Launch Options…",
        "library.inspector.open_steam": "Open in Steam",
        "library.inspector.store_page": "Steam Store Page",
        "library.inspector.reveal_finder": "Reveal in Finder",
        "library.inspector.copy_appid": "Copy AppID",
        "library.inspector.remove": "Remove from macSteam",
        "library.launch_options.title": "Steam Launch Options — %@",
        "library.launch_options.info": "Arguments passed to the game by Steam on launch (stored in localconfig.vdf). Example: -windowed, Wine/CrossOver/GPTK env vars.",
        "library.launch_options.save": "Save",

        // Depots & Builds
        "builds.title": "Depots & Builds",
        "builds.games.placeholder": "Filter games…",
        "builds.variants.title": "Stored Lua Versions / Presets",
        "builds.btn.apply": "Apply Version",
        "builds.btn.save_preset": "Save as Preset…",
        "builds.btn.edit_lua": "Edit Lua…",
        "builds.btn.rename": "Rename…",
        "builds.btn.delete_variant": "Delete Version",
        "builds.depots.title": "Declared Depots & DLCs",
        "builds.depots.search": "Filter depots, DLCs, or manifest GID…",
        "builds.depot.enabled": "Enabled",
        "builds.depot.pinned": "Pinned",
        "builds.depot.download_manifest": "Download .manifest",
        "builds.empty": "Select a game on the left to manage its depots, decryption keys, and builds.",

        // Fixes
        "fixes.title": "Game Fixes",
        "fixes.search.placeholder": "Search games with fixes…",
        "fixes.filter.my_games": "My Games Only",
        "fixes.filter.all_tags": "All Tags",
        "fixes.btn.refresh": "Refresh",
        "fixes.empty": "No fixes found.",
        "fixes.detail.empty": "Select a game to view available fixes.",
        "fixes.btn.download_manifest": "Install Manifest (Pinned)",
        "fixes.btn.apply_fix": "Apply Fix to Game Folder",
        "fixes.btn.revert_fix": "Revert Original Files",
        "fixes.status.applied": "Fix applied",
        "fixes.status.game_not_installed": "Game not installed locally in Steam",

        // Downloads Queue
        "downloads.title": "Downloads",
        "downloads.active.title": "Active & Queued",
        "downloads.history.title": "Download History",
        "downloads.btn.clear_history": "Clear History",
        "downloads.btn.cancel": "Cancel",
        "downloads.btn.retry": "Retry",
        "downloads.empty": "No active downloads or history entries.",

        // Store Plugin
        "plugin.title": "Steam Store Plugin",
        "plugin.subtitle": "Injects the 'Add via LuaTools / macSteam' button directly into Steam Store pages inside the macOS Steam client via CEF bridge.",
        "plugin.status.installed": "Plugin active and ready",
        "plugin.status.not_installed": "Plugin not configured",
        "plugin.row.server": "Local HTTP Server (127.0.0.1:6767)",
        "plugin.row.cef": "Steam CEF Remote Debugging (.cef-enable-remote-debugging · Port 8080)",
        "plugin.row.script": "Frontend Script (luatools.js)",
        "plugin.btn.install": "Install / Enable Plugin",
        "plugin.btn.update": "Update from GitHub",
        "plugin.btn.uninstall": "Uninstall Plugin",
        "plugin.btn.restart_steam": "Restart Steam to Apply",

        // Settings
        "settings.title": "Settings",
        "settings.group.general": "General & Interface",
        "settings.lang.title": "Application Language",
        "settings.lang.system": "System Default (macOS)",
        "settings.hide_whats_new": "Hide Steam 'What's New' shelf",
        "settings.fast_fetch": "FastFetch (auto-download from best available source)",
        "settings.auto_update_apps": "Auto-Update Apps (comment out manifest pins by default)",
        "settings.donate_keys": "Donate spare depot decryption keys to community pool",
        "settings.cef_plugin": "Enable local HTTP server & CEF injector for Steam Store",
        "settings.group.account": "LuaTools Account (lua.tools)",
        "settings.account.guest": "Not signed in (Guest mode)",
        "settings.account.signin_discord": "Sign in with Discord…",
        "settings.account.signin_code": "Redeem Bot Code (6 chars)",
        "settings.account.signout": "Sign Out",
        "settings.account.code_placeholder": "/login code",
        "settings.group.hubcap": "Hubcap API Key (hubcapmanifest.com)",
        "settings.hubcap.placeholder": "Paste your smm_… key",
        "settings.hubcap.save": "Validate & Save",
        "settings.hubcap.clear": "Clear Key",
        "settings.hubcap.refresh": "Refresh Quota",
        "settings.hubcap.configured": "Key configured · Today's usage: %d / %d requests",
        "settings.group.updates": "Updates",
        "settings.updates.auto": "Automatically check for updates",
        "settings.updates.check": "Check for Updates…",

        // Common
        "common.error": "Error",
        "common.cancel": "Cancel",
        "common.save": "Save",
        "common.remove": "Remove",
        "common.ok": "OK",
        "common.loading": "Loading…",
    ]
}
