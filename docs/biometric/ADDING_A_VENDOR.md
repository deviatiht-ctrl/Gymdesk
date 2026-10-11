# GUIDE D'AJOUT D'UN NOUVEAU FABRICANT DE LECTEUR BIOMÉTRIQUE

Ce guide explique pas à pas aux développeurs comment ajouter la prise en charge d'un nouveau fabricant de lecteur d'empreintes dans GymDesk sans modifier le reste du système.

---

## ÉTAPES D'INTÉGRATION

### 1. Identifier les identifiants USB (VID et PID)
Ajoutez les identifiants dans `packages/gymdesk_biometrics/lib/src/supported_readers.json` :
```json
{
  "vendor": "MonFabricant",
  "model": "MonLecteur Pro",
  "vid": "0x1234",
  "pid": "0x5678",
  "supported_platforms": ["windows", "android"]
}
```

### 2. Créer l'adaptateur dérivé de `ReaderVendorAdapter`
Dans `packages/gymdesk_biometrics/lib/src/adapters/` :
```dart
class MonFabricantAdapter implements ReaderVendorAdapter {
  @override
  String get vendorId => 'mon_fabricant';

  @override
  bool supports(UsbIdentity id) => id.vid == '0x1234' && id.pid == '0x5678';

  @override
  Future<FingerprintReader> create(UsbIdentity id) async {
    return MonFabricantReader(id);
  }
}
```

### 3. Implémenter l'interface `FingerprintReader`
Votre classe `MonFabricantReader` doit implémenter :
- `open()` / `close()`
- `events` : flux d'événements (doigt posé, doigt retiré, etc.)
- `capture({Duration timeout, int minQuality})` : retourne un objet `Capture` avec image (optionnelle), gabarit et score de qualité.
- `verify(Template enrolled, Capture probe)` : comparaison 1:1.
- `identify(Capture probe, Iterable<Template> candidates)` : identification 1:N.

### 4. Enregistrer l'adaptateur dans le registre
Dans `packages/gymdesk_biometrics/lib/src/reader_registry.dart` :
```dart
ReaderRegistry.instance.register(MonFabricantAdapter());
```

C'est tout ! Dès que le lecteur est branché, GymDesk le reconnaît, l'affiche dans les paramètres et l'utilise automatiquement pour l'enrôlement et le contrôle de porte.
