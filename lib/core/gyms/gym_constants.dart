/// Constantes et utilitaires d'identification des salles spéciales.
const String jlFitnessGymId = '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3';
const String jlFitnessGymCode = 'JLF';

/// Vérifie de façon robuste si un gym correspond à JL FITNESS.
bool isJlFitnessGym({String? gymId, String? gymCode, String? gymName}) {
  final id = (gymId ?? '').trim().toLowerCase();
  final code = (gymCode ?? '').trim().toUpperCase();
  final name = (gymName ?? '').trim().toUpperCase();

  if (id == jlFitnessGymId) return true;
  if (code == jlFitnessGymCode) return true;
  if (name == 'JL FITNESS' || name.startsWith('JL FIT') || name.contains('JL FITNESS')) {
    return true;
  }

  return false;
}
