// HashStrategy: URL с # (site.com/#/inventory).
// F5 работает без настройки сервера — хэш не отправляется на сервер.
// Не вызываем usePathUrlStrategy() — остаётся дефолтный hash.
void initUrlStrategy() {
  // пусто = hash по умолчанию
}
