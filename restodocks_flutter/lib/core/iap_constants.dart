/// App Store Connect — In-App Purchase.
///
/// Чек-лист для **трёх продуктов кроме уже существующего Pro** (итого 4 SKU в коде):
///
/// 1) **restodocks_ultra_monthly** — Auto-Renewable Subscription, 1 месяц, группа подписок та же,
///    что у Pro (чтобы был upgrade/downgrade). Reference name: e.g. «Ultra Monthly».
///    Цена: уровень ~40 USD (или региональные эквиваленты).
///
/// 2) **restodocks_addon_employee_pack_5** — тип **Consumable** (можно покупать много раз).
///    Display name: «+5 employee slots» / «+5 сотрудников». Ориентир цены ~10 USD.
///    Связанный App Store Review: кратко, что после серверной активации лимит +5 на заведение.
///
/// 3) **restodocks_addon_branch_pack_1** — **Consumable**. Display name: «+1 branch» / «+1 филиал».
///    Ориентир ~10 USD. После сервера — +1 слот филиала на владельца.
///
/// Общее в Connect: Agreements / Paid Apps, налоги, банковский контракт, Shared Secret для
/// verifyReceipt (тот же, что в Edge `billing-verify-apple`). Для подписок — прикрепить к версии
/// приложения в разделе In-App Purchases.
///
/// Идентификаторы ниже должны совпадать с Product ID в App Store Connect **буква в букву**.
const String kRestodocksProMonthlyProductId = 'restodocks_pro_monthly';
const String kRestodocksUltraMonthlyProductId = 'restodocks_ultra_monthly';

/// Расширения (по одному продукту на покупку). Подключение на сервере — по мере готовности;
/// клиент может запрашивать цены для отображения.
const String kRestodocksAddonEmployeePack5ProductId = 'restodocks_addon_employee_pack_5';
const String kRestodocksAddonBranchPack1ProductId = 'restodocks_addon_branch_pack_1';

/// Подписки, которые переводят заведение в Pro / Ultra после billing-verify-apple.
const Set<String> kRestodocksSubscriptionProductIds = {
  kRestodocksProMonthlyProductId,
  kRestodocksUltraMonthlyProductId,
};

/// Все ID для queryProductDetails (подписки + будущие расширения).
const Set<String> kRestodocksAllIapProductIds = {
  kRestodocksProMonthlyProductId,
  kRestodocksUltraMonthlyProductId,
  kRestodocksAddonEmployeePack5ProductId,
  kRestodocksAddonBranchPack1ProductId,
};
