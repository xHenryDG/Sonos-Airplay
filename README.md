# SonosAirBridge

Eine iOS-App, die deine Sonos-Lautsprecher als AirPlay-Gerät in deinem Netzwerk anmeldet – ohne offiziell AirPlay-fähig zu sein.

## Wie es funktioniert

1. Die App sucht per **SSDP/UPnP** alle Sonos-Boxen im lokalen WLAN
2. Du wählst die gewünschten Lautsprecher aus und gibst der Gruppe einen Namen
3. Die App **gruppiert die Sonos-Speaker** per UPnP GroupManagement API
4. Die Gruppe wird als **AirPlay-Empfänger** über Bonjour/mDNS im Netzwerk bekanntgemacht
5. Du kannst dann aus jeder App (Spotify, Apple Music, etc.) über AirPlay streamen

## Voraussetzungen

- Xcode 15 oder neuer
- iPhone mit iOS 16+
- Apple Developer Account (kostenlos reicht für SideStore)
- Alle Geräte im selben WLAN-Netzwerk

## Build & Installation

### Option 1: SideStore (empfohlen)

1. Öffne `SonosAirBridge.xcodeproj` in Xcode
2. Ändere `PRODUCT_BUNDLE_IDENTIFIER` in den Build Settings auf etwas Eigenes, z.B. `com.DEINNAME.sonosairbridge`
3. Wähle dein iPhone als Ziel
4. **Product → Archive**
5. Im Organizer: **Distribute App → Development** → IPA exportieren
6. Übertrage die IPA über AltStore / SideStore auf dein iPhone

### Option 2: Direkt über Xcode

1. Xcode öffnen, iPhone anschließen
2. Team in Signing & Capabilities eintragen
3. **Run** (▶) drücken

## Hinweise

- Das iPhone/iPad muss **im selben WLAN** sein wie die Sonos-Boxen
- Die App muss **geöffnet und aktiv** bleiben während du streamst (oder mit "Background Audio" Entitlement im Hintergrund laufen)
- Bei Sonos-Geräten mit **S2-Firmware** (neuere Generation) funktioniert die UPnP API noch. Ältere S1-Geräte ebenfalls.
- Der AirPlay-Empfänger nutzt Bonjour über `_raop._tcp` – das ist der Standard-Mechanismus

## Projektstruktur

```
SonosAirBridge/
├── SonosAirBridgeApp.swift      # App-Einstiegspunkt
├── ContentView.swift            # Haupt-UI (SwiftUI)
├── SonosDiscovery.swift         # SSDP-Suche im Netzwerk
├── AirPlayBridgeManager.swift   # Sonos-Gruppe + AirPlay-Brücke
└── Info.plist                   # Berechtigungen (Lokales Netzwerk, Bonjour)
```

## Fehlerbehebung

**Keine Lautsprecher gefunden:**
- Stelle sicher, dass iPhone und Sonos im selben WLAN sind
- Prüfe unter Einstellungen → Datenschutz → Lokales Netzwerk, ob die App Zugriff hat
- Firewall/Router-Einstellungen können SSDP-Multicast blockieren

**AirPlay-Gerät erscheint nicht:**
- Bonjour mDNS funktioniert nur im lokalen Netzwerk
- Manchmal hilft es, WLAN kurz aus- und wieder einzuschalten

**Ton kommt nur aus einem Lautsprecher:**
- Die Gruppenbildung kann 2-3 Sekunden dauern – kurz warten nach dem Erstellen

## Lizenz

MIT License – frei verwendbar und veränderbar.
