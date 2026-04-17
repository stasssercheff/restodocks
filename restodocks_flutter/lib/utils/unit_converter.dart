import '../models/culinary_units.dart';
import '../services/localization_service.dart';
import '../services/unit_system_preference_service.dart';

class UnitViewValue {
  const UnitViewValue({
    required this.value,
    required this.unitId,
  });

  final double value;
  final String unitId;
}

class UnitConverter {
  UnitConverter._();

  static const double _gramsPerOunce = 28.3495;
  static const double _gramsPerPound = 453.592;
  static const double _mlPerFlOz = 29.5735;
  static const double _mlPerGallon = 3785.41;

  static String normalizeUnitId(String? unit) {
    final raw = (unit ?? 'g').trim().toLowerCase();
    if (raw == 'г') return 'g';
    if (raw == 'кг') return 'kg';
    if (raw == 'мл') return 'ml';
    if (raw == 'л') return 'l';
    if (raw == 'шт') return 'pcs';
    if (raw == 'галлон') return 'gal';
    if (raw == 'унция') return 'oz';
    return raw;
  }

  static String displayUnitLabel(
      String? rawUnit, LocalizationService loc, UnitSystem system) {
    final unit = preferredDisplayUnit(rawUnit, system);
    return loc.unitLabel(unit);
  }

  static String preferredDisplayUnit(String? rawUnit, UnitSystem system) {
    final u = normalizeUnitId(rawUnit);
    if (system == UnitSystem.metric) {
      switch (u) {
        case 'oz':
          return 'g';
        case 'lb':
          return 'kg';
        case 'fl_oz':
          return 'ml';
        case 'gal':
          return 'l';
        default:
          return u;
      }
    }
    switch (u) {
      case 'g':
        return 'oz';
      case 'kg':
        return 'lb';
      case 'ml':
        return 'fl_oz';
      case 'l':
        return 'gal';
      default:
        return u;
    }
  }

  static UnitViewValue toDisplay({
    required double canonicalValue,
    required String? canonicalUnit,
    required UnitSystem system,
    double? gramsPerPiece,
  }) {
    final normalized = normalizeUnitId(canonicalUnit);
    final target = preferredDisplayUnit(normalized, system);
    if (target == normalized) {
      return UnitViewValue(value: canonicalValue, unitId: normalized);
    }
    final grams = CulinaryUnits.toGrams(
      canonicalValue,
      normalized,
      gramsPerPiece: gramsPerPiece,
    );
    switch (target) {
      case 'oz':
        return UnitViewValue(value: grams / _gramsPerOunce, unitId: target);
      case 'lb':
        return UnitViewValue(value: grams / _gramsPerPound, unitId: target);
      case 'fl_oz':
        return UnitViewValue(value: grams / _mlPerFlOz, unitId: target);
      case 'gal':
        return UnitViewValue(value: grams / _mlPerGallon, unitId: target);
      case 'g':
      case 'kg':
      case 'ml':
      case 'l':
      default:
        return UnitViewValue(
          value: CulinaryUnits.fromGrams(grams, target, gramsPerPiece: gramsPerPiece),
          unitId: target,
        );
    }
  }

  static double fromDisplay({
    required double displayValue,
    required String? canonicalUnit,
    required UnitSystem system,
    double? gramsPerPiece,
  }) {
    final canonical = normalizeUnitId(canonicalUnit);
    final displayUnit = preferredDisplayUnit(canonical, system);
    if (displayUnit == canonical) return displayValue;

    final grams = switch (displayUnit) {
      'oz' => displayValue * _gramsPerOunce,
      'lb' => displayValue * _gramsPerPound,
      'fl_oz' => displayValue * _mlPerFlOz,
      'gal' => displayValue * _mlPerGallon,
      _ => CulinaryUnits.toGrams(displayValue, displayUnit, gramsPerPiece: gramsPerPiece),
    };
    return CulinaryUnits.fromGrams(
      grams,
      canonical,
      gramsPerPiece: gramsPerPiece,
    );
  }

  static double roundUi(double value, {int fractionDigits = 2}) {
    final p = fractionDigits < 0 ? 0 : fractionDigits;
    return double.parse(value.toStringAsFixed(p));
  }
}
