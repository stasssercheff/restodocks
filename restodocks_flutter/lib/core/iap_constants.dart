/// App Store Connect — In-App Purchase identifiers.
/// Must match Product ID values in App Store Connect exactly (case-sensitive).
const String kRestodocksProMonthlyProductId = 'Pro_monthly';
const String kRestodocksUltraMonthlyProductId = 'Ultra_monthly';

/// Establishment slot add-ons (consumables).
const String kRestodocksAddonBranchPack1ProductId =
    '1_extra_establishment_monthly';
const String kRestodocksAddonBranchPack3ProductId =
    '3_extra_establishment_monthly';
const String kRestodocksAddonBranchPack5ProductId =
    '5_extra_establishment_monthly';
const String kRestodocksAddonBranchPack10ProductId =
    '10_extra_establishment_monthly';

/// Employee slot add-ons (consumables).
const String kRestodocksAddonEmployeePack5ProductId = '5_extra_employee_monthly';
const String kRestodocksAddonEmployeePack10ProductId =
    '10_extra_employee_monthly';
const String kRestodocksAddonEmployeePack15ProductId =
    '15_extra_employee_monthly';
const String kRestodocksAddonEmployeePack20ProductId =
    '20_extra_employee_monthly';

/// Display order in subscription sheet.
const List<String> kRestodocksAddonProductIdOrder = [
  kRestodocksAddonBranchPack1ProductId,
  kRestodocksAddonBranchPack3ProductId,
  kRestodocksAddonBranchPack5ProductId,
  kRestodocksAddonBranchPack10ProductId,
  kRestodocksAddonEmployeePack5ProductId,
  kRestodocksAddonEmployeePack10ProductId,
  kRestodocksAddonEmployeePack15ProductId,
  kRestodocksAddonEmployeePack20ProductId,
];

const Set<String> kRestodocksAddonProductIds = {
  kRestodocksAddonBranchPack1ProductId,
  kRestodocksAddonBranchPack3ProductId,
  kRestodocksAddonBranchPack5ProductId,
  kRestodocksAddonBranchPack10ProductId,
  kRestodocksAddonEmployeePack5ProductId,
  kRestodocksAddonEmployeePack10ProductId,
  kRestodocksAddonEmployeePack15ProductId,
  kRestodocksAddonEmployeePack20ProductId,
};

/// Подписки, которые переводят заведение в Pro / Ultra после billing-verify-apple.
const Set<String> kRestodocksSubscriptionProductIds = {
  kRestodocksProMonthlyProductId,
  kRestodocksUltraMonthlyProductId,
};

/// Все ID для queryProductDetails (подписки + будущие расширения).
const Set<String> kRestodocksAllIapProductIds = {
  kRestodocksProMonthlyProductId,
  kRestodocksUltraMonthlyProductId,
  ...kRestodocksAddonProductIds,
};
