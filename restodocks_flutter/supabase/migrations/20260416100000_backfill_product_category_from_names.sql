-- Заполнение products.category, если при массовом импорте поле пустое.
-- Эвристика по lower(name || names::text): не заменяет уже заданные непустые категории.
-- Целевые значения — как в каталоге 20260227240000 (meat, seafood, vegetables, …).
-- Расширение списка продуктов до ~3500 и т.п. — отдельный импорт/SQL; здесь только UPDATE существующих строк.

UPDATE public.products p
SET category = v.cat
FROM (
  SELECT
    pr.id,
    CASE
      -- Морепродукты / рыба (раньше мяса по «fish» в названии)
      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%рыб%', '%fish%', '%лосос%', '%salmon%', '%тунец%', '%tuna%', '%форель%', '%trout%',
        '%кревет%', '%shrimp%', '%кальмар%', '%squid%', '%осьминог%', '%octopus%', '%миди%',
        '%mussel%', '%устриц%', '%oyster%', '%сельд%', '%herring%', '%треск%', '%cod%',
        '%скумбр%', '%mackerel%', '%филе рыб%', '%морепродукт%', '%seafood%', '%икра рыб%',
        '%anchov%', '%сардин%', '%sardine%', '%фаланг%', '%гребеш%', '%scallop%'
      ]) THEN 'seafood'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%яйц%', '%egg%', '%яйцо%'
      ]) THEN 'eggs'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%молок%', '%milk%', '%сыр%', '%cheese%', '%творог%', '%cottage%', '%сливк%', '%cream%',
        '%йогурт%', '%yogurt%', '%кефир%', '%kef%', '%сметан%', '%ряженк%', '%масло сливоч%',
        '%butter%', '%моцарел%', '%mozzarella%', '%рикотт%', '%ricotta%', '%пармезан%',
        '%parmesan%', '%сырок%'
      ]) THEN 'dairy'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%масло олив%', '%olive oil%', '%подсолнечн%', '%sunflower%', '%кунжутн%масл%',
        '%sesame oil%', '%рапсов%масл%', '%canola%', '%кокосов%масл%', '%grapeseed%'
      ]) THEN 'oils'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%овощ%', '%veget%', '%морков%', '%carrot%', '%лук%', '%onion%', '%картоф%', '%potato%',
        '%помидор%', '%tomato%', '%огур%', '%cucumber%', '%капуст%', '%cabbage%', '%салат%',
        '%lettuce%', '%шпинат%', '%spinach%', '%брокколи%', '%broccoli%', '%чеснок%', '%garlic%',
        '%перец болгар%', '%баклаж%', '%eggplant%', '%кабач%', '%zucchini%', '%тыкв%', '%pumpkin%',
        '%свёкл%', '%beet%', '%редис%', '%radish%', '%руккол%', '%arugula%', '%петрушка%',
        '%parsley%', '%укроп%', '%dill%', '%сельдер%', '%celery%', '%спаржа%', '%asparagus%',
        '%гриб %', '%гриб,%', '%грибы%', '%mushroom%'
      ]) THEN 'vegetables'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%фрукт%', '%fruit%', '%яблок%', '%apple%', '%банан%', '%banana%', '%апельсин%', '%orange%',
        '%лимон%', '%lemon%', '%груш%', '%pear%', '%персик%', '%peach%', '%виноград%', '%grape%',
        '%клубник%', '%strawber%', '%малин%', '%raspber%', '%черник%', '%blueber%', '%ягод%',
        '%berry%', '%ананас%', '%pineapple%', '%манго%', '%mango%', '%киви%', '%kiwi%'
      ]) THEN 'fruits'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%фасоль%', '%bean%', '%горох%', '%peas%', '%чечевиц%', '%lentil%', '%нут%', '%chickpea%',
        '%соя%', '%soy%', '%бобов%'
      ]) THEN 'legumes'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%рис%', '%rice%', '%греч%', '%buckwheat%', '%перлов%', '%barley%', '%овсян%', '%oat%',
        '%пшен%', '%wheat%', '%мука%', '%flour%', '%крупа%', '%макарон%', '%pasta%', '%спагет%',
        '%spaghetti%', '%лапша%', '%noodle%', '%булгур%', '%bulgur%', '%couscous%', '%кускус%',
        '%киноа%', '%quinoa%', '%полент%', '%polenta%'
      ]) THEN 'grains'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%орех%', '%nut%', '%миндаль%', '%almond%', '%арахис%', '%peanut%', '%фундук%', '%hazel%',
        '%кешью%', '%cashew%', '%фисташ%', '%pistach%'
      ]) THEN 'nuts'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%перец ч%', '%перец б%', '%pepper%', '%соль%', '%salt%', '%паприк%', '%paprika%',
        '%куркум%', '%curcuma%', '%корица%', '%cinnamon%', '%мускат%', '%nutmeg%', '%лавров%',
        '%bay leaf%', '%розмарин%', '%rosemary%', '%тимьян%', '%thyme%', '%базилик%', '%basil%',
        '%орегано%', '%oregano%', '%кинза%', '%cilantro%', '%кориандр%', '%имбир%', '%ginger%',
        '%чили%', '%chili%', '%карри%', '%curry%', '%приправ%', '%спец%', '%spice%', '%ваниль%',
        '%vanilla%'
      ]) THEN 'spices'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%сок%', '%juice%', '%вода%', '%water%', '%напиток%', '%beverage%', '%cola%', '%пепси%',
        '%pepsi%', '%sprite%', '%пиво%', '%beer%', '%вино%', '%wine%', '%шампан%', '%champagne%',
        '%коньяк%', '%cognac%', '%виски%', '%whiskey%', '%ром%', '%rum%', '%водка%', '%vodka%',
        '%чай%', '%tea%', '%кофе%', '%coffee%', '%какао%', '%cocoa%', '%энергет%', '%energy drink%'
      ]) THEN 'beverages'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%хлеб%', '%bread%', '%булк%', '%bun%', '%багет%', '%baguette%', '%круасс%', '%croissant%',
        '%бриош%', '%brioche%', '%пирог%', '%pie%', '%торт%', '%cake%', '%печенье%', '%cookie%',
        '%бисквит%', '%biscuit%', '%маффин%', '%muffin%', '%вафл%', '%waffle%', '%пончик%', '%donut%',
        '%слоен%', '%pastry%'
      ]) THEN 'bakery'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%уксус%', '%vinegar%', '%соус%', '%sauce%', '%кетчуп%', '%ketchup%', '%майонез%', '%mayo%',
        '%горчиц%', '%mustard%', '%сахар%', '%sugar%', '%мёд%', '%honey%', '%джем%', '%jam%',
        '%консерв%', '%крахмал%', '%starch%', '%дрожж%', '%yeast%', '%паста томат%', '%tomato paste%'
      ]) THEN 'pantry'

      WHEN lower(concat_ws(' ', pr.name, coalesce(pr.names::text, ''))) LIKE ANY (ARRAY[
        '%говядин%', '%beef%', '%свинин%', '%pork%', '%баранин%', '%lamb%', '%телят%', '%veal%',
        '%курин%', '%chicken%', '%индейк%', '%turkey%', '%утин%', '%duck%', '%гус%', '%goose%',
        '%перепел%', '%quail%', '%фазан%', '%pheasant%', '%кролик%', '%rabbit%', '%мясо%', '%meat%',
        '%фарш%', '%ground%', '%стейк%', '%steak%', '%котлет%', '%cutlet%', '%шницель%',
        '%бекон%', '%bacon%', '%ветчин%', '%ham%', '%салями%', '%salami%', '%колбас%', '%sausage%',
        '%печень%', '%liver%', '%сердц%', '%heart%', '%язык%', '%tongue%', '%почк%', '%kidney%',
        '%рубец%', '%tripe%', '%ребр%', '%ribs%', '%шашлык%', '%prosciutto%', '%chorizo%',
        '%mortadella%', '%pancetta%', '%сало%', '%суджук%', '%копч%', '%фуа%', '%foie%'
      ]) THEN 'meat'

      ELSE 'misc'
    END AS cat
  FROM public.products pr
  WHERE pr.category IS NULL OR trim(pr.category) = ''
) v
WHERE p.id = v.id;

COMMENT ON COLUMN public.products.category IS
  'Категория номенклатуры (meat, seafood, vegetables, …). При импорте без категории — backfill по названию (миграция 20260416100000) или misc.';
