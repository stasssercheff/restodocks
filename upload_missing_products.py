#!/usr/bin/env python3
"""
Дополняет базу продуктов до ~3000.
- Берёт world_products.json (3000 записей с английскими названиями)
- Исключает дубли с уже существующими в Supabase
- Добавляет ru переводы через встроенный словарь
- Загружает через Supabase REST API пачками по 100

Нужен SERVICE_ROLE_KEY (или anon key если RLS позволяет insert).
"""

import json
import urllib.request
import urllib.error
import uuid
import time
import sys

# ─── Config ─────────────────────────────────────────────────────────────────
SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
# anon key (будет работать только если RLS разрешает INSERT для anon или auth.user)
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"
# Передать service role key через аргумент: python3 upload_missing_products.py <service_key>
SERVICE_KEY = sys.argv[1] if len(sys.argv) > 1 else None
API_KEY = SERVICE_KEY or ANON_KEY

BATCH_SIZE = 100
TARGET_TOTAL = 3000

# ─── EN→RU translations dictionary ──────────────────────────────────────────
EN_RU = {
    # Vegetables
    "Tomato": "Томат", "Potato": "Картофель", "Onion": "Лук репчатый",
    "Carrot": "Морковь", "Cucumber": "Огурец", "Bell Pepper": "Перец болгарский",
    "Broccoli": "Брокколи", "Spinach": "Шпинат", "Lettuce": "Салат-латук",
    "Cabbage": "Капуста белокочанная", "Garlic": "Чеснок", "Ginger": "Имбирь",
    "Eggplant": "Баклажан", "Zucchini": "Кабачок", "Celery": "Сельдерей",
    "Radish": "Редис", "Beetroot": "Свёкла", "Asparagus": "Спаржа",
    "Artichoke": "Артишок", "Cauliflower": "Цветная капуста",
    "Sweet Potato": "Батат", "Pumpkin": "Тыква", "Leek": "Лук-порей",
    "Brussels Sprouts": "Брюссельская капуста", "Kale": "Кале",
    "Turnip": "Репа", "Parsnip": "Пастернак", "Kohlrabi": "Кольраби",
    "Chard": "Мангольд", "Endive": "Эндивий", "Fennel": "Фенхель",
    "Arugula": "Руккола", "Watercress": "Кресс-салат", "Bok Choy": "Пак-чой",
    "Daikon": "Дайкон", "Jerusalem Artichoke": "Топинамбур",
    "Sorrel": "Щавель", "Rhubarb": "Ревень", "Pak Choy": "Пак-чой",
    "Green Onion": "Зелёный лук", "Spring Onion": "Зелёный лук",
    "Shallot": "Шалот", "Chive": "Лук-резанец", "Dill": "Укроп",
    "Parsley": "Петрушка", "Coriander": "Кинза", "Basil": "Базилик",
    "Mint": "Мята", "Thyme": "Тимьян", "Rosemary": "Розмарин",
    "Oregano": "Орегано", "Sage": "Шалфей", "Tarragon": "Эстрагон",
    "Marjoram": "Майоран", "Bay Leaf": "Лавровый лист",
    "Hot Pepper": "Острый перец", "Chili Pepper": "Перец чили",
    "Green Pepper": "Зелёный перец", "Red Pepper": "Красный перец",
    "Yellow Pepper": "Жёлтый перец", "Cherry Tomato": "Томат черри",
    "Sun-dried Tomato": "Вяленый томат", "Green Beans": "Стручковая фасоль",
    "Snow Peas": "Сахарный горошек", "Sugar Snap Peas": "Сахарный горошек",
    "Corn": "Кукуруза", "Sweet Corn": "Кукуруза сахарная",
    "Bamboo Shoots": "Побеги бамбука", "Bean Sprouts": "Ростки сои",
    "Water Chestnut": "Водяной орех", "Lotus Root": "Корень лотоса",
    "Taro": "Таро", "Cassava": "Маниок", "Yam": "Ямс",
    "White Cabbage": "Белокочанная капуста", "Red Cabbage": "Красная капуста",
    "Savoy Cabbage": "Савойская капуста", "Napa Cabbage": "Пекинская капуста",
    "Chinese Cabbage": "Пекинская капуста", "Radicchio": "Радиккио",
    "Frisee": "Фризе", "Escarole": "Эскариол", "Romaine": "Романо",
    "Iceberg Lettuce": "Айсберг", "Butterhead Lettuce": "Масляный салат",
    "Arrowroot": "Маранта", "Okra": "Окра", "Plantain": "Подорожник банановый",
    "Jicama": "Хикама", "Sunchoke": "Топинамбур", "Celeriac": "Корневой сельдерей",
    "Rutabaga": "Брюква", "Horseradish": "Хрен", "Wasabi": "Васаби",
    "Lemongrass": "Лемонграсс", "Galangal": "Галангал", "Turmeric Root": "Куркума свежая",
    "White Asparagus": "Белая спаржа", "Purple Asparagus": "Фиолетовая спаржа",
    "Baby Spinach": "Молодой шпинат", "Microgreens": "Микрозелень",
    "Purple Cabbage": "Красная капуста", "Butternut Squash": "Мускатная тыква",
    "Acorn Squash": "Желудевая тыква", "Spaghetti Squash": "Спагетти-тыква",
    "Delicata Squash": "Делаката", "Kabocha": "Тыква кабоча",
    "White Onion": "Белый лук", "Yellow Onion": "Жёлтый лук",
    "Red Onion": "Красный лук", "Pearl Onion": "Жемчужный лук",
    "Cipollini": "Чиполлини", "Vidalia Onion": "Лук видалия",
    "Wax Beans": "Жёлтая стручковая фасоль", "Purple Green Beans": "Фиолетовая стручковая фасоль",
    "Edamame": "Эдамаме", "Snap Peas": "Горошек", "Garden Peas": "Горошек",
    "Black-eyed Peas": "Вигна черноглазая",

    # Fruits
    "Apple": "Яблоко", "Banana": "Банан", "Orange": "Апельсин",
    "Lemon": "Лимон", "Grape": "Виноград", "Strawberry": "Клубника",
    "Blueberry": "Черника", "Raspberry": "Малина", "Pineapple": "Ананас",
    "Mango": "Манго", "Peach": "Персик", "Pear": "Груша",
    "Plum": "Слива", "Cherry": "Вишня", "Apricot": "Абрикос",
    "Lime": "Лайм", "Watermelon": "Арбуз", "Melon": "Дыня",
    "Kiwi": "Киви", "Papaya": "Папайя", "Pomegranate": "Гранат",
    "Fig": "Инжир", "Date": "Финик", "Avocado": "Авокадо",
    "Coconut": "Кокос", "Passion Fruit": "Маракуйя", "Lychee": "Личи",
    "Guava": "Гуава", "Persimmon": "Хурма", "Quince": "Айва",
    "Grapefruit": "Грейпфрут", "Mandarin": "Мандарин",
    "Tangerine": "Мандарин", "Pomelo": "Помело", "Kumquat": "Кумкват",
    "Dragon Fruit": "Драконий фрукт", "Starfruit": "Карамбола",
    "Jackfruit": "Джекфрут", "Durian": "Дуриан", "Tamarind": "Тамаринд",
    "Rambutan": "Рамбутан", "Mangosteen": "Мангостин", "Longan": "Лонган",
    "Blackberry": "Ежевика", "Gooseberry": "Крыжовник",
    "Cranberry": "Клюква", "Currant": "Смородина",
    "Black Currant": "Чёрная смородина", "Red Currant": "Красная смородина",
    "White Currant": "Белая смородина", "Elderberry": "Бузина",
    "Boysenberry": "Бойзенберри", "Loganberry": "Логанберри",
    "Mulberry": "Шелковица", "Cloudberry": "Морошка",
    "Lingonberry": "Брусника", "Bilberry": "Черника",
    "Huckleberry": "Черника американская", "Serviceberry": "Ирга",
    "Aronia": "Арония", "Sea Buckthorn": "Облепиха",
    "Physalis": "Физалис", "Cape Gooseberry": "Физалис",
    "Tomatillo": "Томатилло", "Feijoa": "Фейхоа",
    "Cherimoya": "Черимойя", "Sapodilla": "Сапота",
    "Soursop": "Саурсоп", "Breadfruit": "Хлебное дерево",
    "Noni": "Нони", "Acai": "Асаи", "Camu Camu": "Каму-каму",
    "Miracle Fruit": "Чудесная ягода", "Nance": "Нанс",
    "Mamey Sapote": "Мамей", "Black Sapote": "Чёрная сапота",
    "White Sapote": "Белая сапота", "Canistel": "Канистел",
    "Lucuma": "Лукума", "Cupuacu": "Купуасу",
    "Dried Apple": "Сушёное яблоко", "Dried Apricot": "Курага",
    "Raisin": "Изюм", "Prune": "Чернослив", "Dried Fig": "Сушёный инжир",
    "Dried Mango": "Сушёное манго", "Dried Pineapple": "Сушёный ананас",
    "Dried Cranberry": "Сушёная клюква", "Dried Cherry": "Сушёная вишня",
    "Dried Blueberry": "Сушёная черника", "Dried Banana": "Сушёный банан",

    # Meat
    "Chicken Breast": "Куриная грудка", "Chicken Thigh": "Куриное бедро",
    "Beef Tenderloin": "Говяжья вырезка", "Beef Ground": "Говяжий фарш",
    "Pork Tenderloin": "Свиная вырезка", "Lamb Chop": "Баранья котлета",
    "Turkey Breast": "Индейка грудка", "Veal Cutlet": "Телячья котлета",
    "Duck Breast": "Утиная грудка", "Rabbit Meat": "Крольчатина",
    "Beef Ribeye": "Говяжий рибай", "Beef Sirloin": "Говяжий сирлоин",
    "Beef Brisket": "Говяжья грудинка", "Beef Chuck": "Говяжий чак",
    "Beef Round": "Говяжий окорок", "Pork Belly": "Свиная грудинка",
    "Pork Shoulder": "Свиная лопатка", "Pork Ribs": "Свиные рёбра",
    "Pork Loin": "Свиная корейка", "Pork Neck": "Свиная шея",
    "Lamb Leg": "Баранья нога", "Lamb Shoulder": "Баранья лопатка",
    "Lamb Rack": "Баранья корейка", "Lamb Ground": "Бараний фарш",
    "Veal Osso Buco": "Телячья рулька", "Veal Scallopini": "Тонкий телячий шницель",
    "Beef Oxtail": "Говяжий хвост", "Beef Tongue": "Говяжий язык",
    "Beef Heart": "Говяжье сердце", "Beef Liver": "Говяжья печень",
    "Beef Kidney": "Говяжьи почки", "Beef Tripe": "Говяжий рубец",
    "Pork Heart": "Свиное сердце", "Pork Liver": "Свиная печень",
    "Pork Kidney": "Свиные почки", "Chicken Liver": "Куриная печень",
    "Chicken Wings": "Куриные крылья", "Chicken Drumstick": "Куриная голень",
    "Chicken Whole": "Целая курица", "Duck Leg": "Утиная нога",
    "Duck Whole": "Целая утка", "Goose Breast": "Гусиная грудка",
    "Turkey Thigh": "Бедро индейки", "Turkey Ground": "Индюшиный фарш",
    "Venison": "Оленина", "Wild Boar": "Дикий кабан",
    "Bison": "Бизон", "Buffalo": "Буйвол",
    "Horse Meat": "Конина", "Goat Meat": "Козлятина",
    "Quail": "Перепел", "Pheasant": "Фазан",
    "Ostrich": "Страус", "Emu": "Эму",
    "Crocodile": "Крокодил", "Kangaroo": "Кенгуру",

    # Fish
    "Salmon": "Лосось", "Tuna": "Тунец", "Cod": "Треска",
    "Sea Bass": "Морской окунь", "Halibut": "Палтус",
    "Mackerel": "Скумбрия", "Herring": "Сельдь", "Sardine": "Сардина",
    "Trout": "Форель", "Carp": "Карп", "Pike": "Щука",
    "Perch": "Окунь", "Catfish": "Сом", "Tilapia": "Тилапия",
    "Snapper": "Снаппер", "Grouper": "Групер", "Mahi-Mahi": "Махи-махи",
    "Swordfish": "Меч-рыба", "Shark": "Акула",
    "Anchovy": "Анчоус", "Sprat": "Шпрот", "Whiting": "Мерланг",
    "Haddock": "Пикша", "Pollock": "Минтай", "Sole": "Морской язык",
    "Turbot": "Тюрбо", "Plaice": "Камбала", "Flounder": "Камбала-флаундер",
    "Atlantic Salmon": "Атлантический лосось", "Pacific Salmon": "Тихоокеанский лосось",
    "Sockeye Salmon": "Нерка", "Coho Salmon": "Кижуч",
    "Pink Salmon": "Горбуша", "Chum Salmon": "Кета",
    "Chinook Salmon": "Чавыча", "Sea Trout": "Кумжа",
    "Rainbow Trout": "Радужная форель", "Brown Trout": "Ручьевая форель",
    "Brook Trout": "Американская палия", "Lake Trout": "Озёрная форель",
    "Arctic Char": "Арктический гольц", "Grayling": "Хариус",
    "Sturgeon": "Осётр", "Beluga": "Белуга", "Sterlet": "Стерлядь",
    "Bream": "Лещ", "Roach": "Плотва", "Tench": "Линь",
    "Ruffe": "Ёрш", "Zander": "Судак", "Burbot": "Налим",
    "Eel": "Угорь", "Lamprey": "Минога", "Smelt": "Корюшка",
    "Capelin": "Мойва", "Vendace": "Ряпушка",
    "Bluefish": "Луфарь", "Pompano": "Помпано",
    "Amberjack": "Янтарная рыба", "Cobia": "Кобия",
    "Wahoo": "Вахоо", "Barracuda": "Барракуда",
    "Yellowtail": "Желтохвост", "Kingfish": "Королевская макрель",
    "Albacore Tuna": "Длиннопёрый тунец", "Bluefin Tuna": "Синепёрый тунец",
    "Yellowfin Tuna": "Желтопёрый тунец", "Skipjack Tuna": "Полосатый тунец",

    # Seafood
    "Shrimp": "Креветки", "Prawn": "Тигровая креветка",
    "Lobster": "Омар", "Crab": "Краб", "Squid": "Кальмар",
    "Octopus": "Осьминог", "Scallop": "Гребешок", "Mussel": "Мидия",
    "Oyster": "Устрица", "Clam": "Моллюск", "Crayfish": "Рак",
    "King Crab": "Краб-стригун", "Snow Crab": "Снежный краб",
    "Dungeness Crab": "Дунгенесский краб", "Blue Crab": "Голубой краб",
    "Tiger Shrimp": "Тигровые креветки", "King Prawn": "Королевская креветка",
    "Langoustine": "Лангустин", "Spiny Lobster": "Лангуст",
    "Sea Urchin": "Морской ёж", "Sea Cucumber": "Голотурия",
    "Abalone": "Морское ухо", "Periwinkle": "Литорина",
    "Whelk": "Трубач", "Cockle": "Сердцевидка",
    "Razor Clam": "Бритвенный моллюск", "Geoduck": "Геодак",
    "Nautilus": "Наутилус", "Cuttlefish": "Каракатица",
    "Sea Snail": "Морская улитка", "Conch": "Конх",
    "Jellyfish": "Медуза", "Sea Weed": "Морские водоросли",
    "Nori": "Нори", "Wakame": "Вакаме", "Kelp": "Ламинария",
    "Dulse": "Дульсе", "Hijiki": "Хидзики", "Kombu": "Комбу",
    "Agar Agar": "Агар-агар",

    # Dairy
    "Milk": "Молоко", "Cream": "Сливки", "Butter": "Сливочное масло",
    "Cheese": "Сыр", "Yogurt": "Йогурт", "Sour Cream": "Сметана",
    "Cottage Cheese": "Творог", "Ricotta": "Рикотта", "Mozzarella": "Моцарелла",
    "Parmesan": "Пармезан", "Cheddar": "Чеддер", "Brie": "Бри",
    "Camembert": "Камамбер", "Roquefort": "Рокфор", "Gorgonzola": "Горгонзола",
    "Mascarpone": "Маскарпоне", "Cream Cheese": "Сливочный сыр",
    "Feta": "Фета", "Halloumi": "Халлуми", "Gouda": "Гауда",
    "Edam": "Эдам", "Emmental": "Эмменталь", "Gruyere": "Грюйер",
    "Fontina": "Фонтина", "Provolone": "Проволоне", "Asiago": "Азиаго",
    "Pecorino": "Пекорино", "Manchego": "Манчего",
    "Whole Milk": "Цельное молоко", "Skim Milk": "Обезжиренное молоко",
    "2% Milk": "Молоко 2%", "Heavy Cream": "Жирные сливки",
    "Whipping Cream": "Взбитые сливки", "Half and Half": "Сливки 10%",
    "Buttermilk": "Пахта", "Kefir": "Кефир", "Acidophilus Milk": "Ацидофилин",
    "Ryazhenka": "Ряженка", "Varenets": "Варенец",
    "Condensed Milk": "Сгущённое молоко", "Evaporated Milk": "Топлёное молоко",
    "Powdered Milk": "Сухое молоко", "Ghee": "Гхи",
    "Creme Fraiche": "Крем-фреш", "Clotted Cream": "Клотид крем",
    "Quark": "Кварк", "Fromage Blanc": "Белый сыр",
    "Burrata": "Буррата", "Stracciatella": "Страчателла",
    "Scamorza": "Скаморца", "Raclette": "Раклет",
    "Taleggio": "Таледжо", "Limburger": "Лимбургер",
    "String Cheese": "Сулугуни", "Labneh": "Лабне",
    "Paneer": "Панир", "Queso Fresco": "Свежий сыр",

    # Eggs
    "Chicken Egg": "Куриное яйцо", "Quail Egg": "Перепелиное яйцо",
    "Duck Egg": "Утиное яйцо", "Goose Egg": "Гусиное яйцо",
    "Turkey Egg": "Яйцо индейки", "Ostrich Egg": "Страусиное яйцо",
    "Egg White": "Яичный белок", "Egg Yolk": "Яичный желток",
    "Whole Egg": "Целое яйцо", "Dried Egg": "Яичный порошок",
    "Salted Egg": "Солёное яйцо", "Century Egg": "Столетнее яйцо",
    "Caviar": "Чёрная икра", "Red Caviar": "Красная икра",
    "Salmon Roe": "Икра лосося", "Tobiko": "Тобико", "Masago": "Масаго",

    # Grains
    "Rice": "Рис", "Wheat": "Пшеница", "Oats": "Овсянка",
    "Barley": "Ячмень", "Rye": "Рожь", "Corn": "Кукуруза",
    "Quinoa": "Киноа", "Millet": "Пшено", "Buckwheat": "Гречка",
    "Bulgur": "Булгур", "Couscous": "Кус-кус", "Amaranth": "Амарант",
    "Teff": "Теф", "Spelt": "Полба", "Kamut": "Камут",
    "Farro": "Фарро", "Freekeh": "Фрике", "Triticale": "Тритикале",
    "Sorghum": "Сорго", "Lentil": "Чечевица",
    "All-Purpose Flour": "Пшеничная мука", "Bread Flour": "Хлебная мука",
    "Whole Wheat Flour": "Цельнозерновая мука", "Rye Flour": "Ржаная мука",
    "Almond Flour": "Миндальная мука", "Coconut Flour": "Кокосовая мука",
    "Rice Flour": "Рисовая мука", "Corn Flour": "Кукурузная мука",
    "Tapioca Flour": "Тапиоковая мука", "Chickpea Flour": "Нутовая мука",
    "Semolina": "Манная крупа", "Polenta": "Поленда",
    "Cornmeal": "Кукурузная крупа", "Hominy": "Хомини",
    "Grits": "Крупа гриц", "Arborio Rice": "Рис арборио",
    "Basmati Rice": "Басмати", "Jasmine Rice": "Жасминовый рис",
    "Brown Rice": "Коричневый рис", "Wild Rice": "Дикий рис",
    "Sticky Rice": "Клейкий рис", "Sushi Rice": "Рис для суши",

    # Nuts & Seeds
    "Almond": "Миндаль", "Walnut": "Грецкий орех", "Cashew": "Кешью",
    "Pistachio": "Фисташки", "Hazelnut": "Фундук", "Pecan": "Пекан",
    "Macadamia": "Макадамия", "Brazil Nut": "Бразильский орех",
    "Pine Nut": "Кедровый орех", "Peanut": "Арахис",
    "Chestnut": "Каштан", "Sunflower Seeds": "Семечки подсолнуха",
    "Pumpkin Seeds": "Тыквенные семечки", "Sesame": "Кунжут",
    "Flax Seeds": "Льняное семя", "Chia Seeds": "Семена чиа",
    "Hemp Seeds": "Конопляные семена", "Poppy Seeds": "Мак",
    "Caraway Seeds": "Тмин", "Coriander Seeds": "Семена кориандра",
    "Fennel Seeds": "Семена фенхеля", "Cumin Seeds": "Семена зиры",
    "Nigella Seeds": "Чернушка", "Mustard Seeds": "Зёрна горчицы",
    "Cardamom Seeds": "Семена кардамона",

    # Legumes
    "Black Beans": "Чёрная фасоль", "Kidney Beans": "Красная фасоль",
    "White Beans": "Белая фасоль", "Pinto Beans": "Пёстрая фасоль",
    "Navy Beans": "Морская фасоль", "Chickpeas": "Нут",
    "Red Lentils": "Красная чечевица", "Green Lentils": "Зелёная чечевица",
    "Black Lentils": "Чёрная чечевица", "Brown Lentils": "Коричневая чечевица",
    "Yellow Split Peas": "Жёлтый горох", "Green Split Peas": "Зелёный горох",
    "Mung Beans": "Маш", "Adzuki Beans": "Адзуки", "Fava Beans": "Бобы",
    "Lima Beans": "Бобы лима", "Cannellini Beans": "Канеллини",
    "Borlotti Beans": "Борлотти", "Dragon Tongue Beans": "Пёстрая фасоль",
    "Soybean": "Соя", "Tofu": "Тофу", "Tempeh": "Темпе",
    "Miso": "Мисо", "Edamame Beans": "Эдамаме",

    # Oils & Fats
    "Olive Oil": "Оливковое масло", "Sunflower Oil": "Подсолнечное масло",
    "Vegetable Oil": "Растительное масло", "Coconut Oil": "Кокосовое масло",
    "Avocado Oil": "Масло авокадо", "Sesame Oil": "Кунжутное масло",
    "Flaxseed Oil": "Льняное масло", "Canola Oil": "Рапсовое масло",
    "Corn Oil": "Кукурузное масло", "Peanut Oil": "Арахисовое масло",
    "Grapeseed Oil": "Масло из виноградных косточек",
    "Walnut Oil": "Масло грецкого ореха", "Hazelnut Oil": "Масло фундука",
    "Almond Oil": "Миндальное масло", "Pumpkin Seed Oil": "Тыквенное масло",
    "Rice Bran Oil": "Масло рисовых отрубей", "Palm Oil": "Пальмовое масло",
    "MCT Oil": "МСТ масло", "Hemp Oil": "Конопляное масло",
    "Truffle Oil": "Трюфельное масло", "Chili Oil": "Масло чили",
    "Garlic Oil": "Чесночное масло", "Infused Oil": "Ароматизированное масло",
    "Lard": "Свиной жир", "Tallow": "Говяжий жир", "Duck Fat": "Утиный жир",
    "Shortening": "Кулинарный жир", "Margarine": "Маргарин",

    # Spices
    "Black Pepper": "Чёрный перец", "White Pepper": "Белый перец",
    "Red Pepper Flakes": "Хлопья красного перца", "Paprika": "Паприка",
    "Cumin": "Зира", "Coriander": "Кориандр", "Turmeric": "Куркума",
    "Cinnamon": "Корица", "Cloves": "Гвоздика", "Nutmeg": "Мускатный орех",
    "Cardamom": "Кардамон", "Star Anise": "Звёздчатый анис", "Anise": "Анис",
    "Saffron": "Шафран", "Fenugreek": "Пажитник", "Allspice": "Душистый перец",
    "Cayenne Pepper": "Кайенский перец", "Smoked Paprika": "Копчёная паприка",
    "Curry Powder": "Карри порошок", "Garam Masala": "Гарам масала",
    "Chinese Five Spice": "Пять специй", "Za'atar": "Заатар",
    "Sumac": "Сумак", "Baharat": "Бахарат", "Ras el Hanout": "Рас-эль-ханут",
    "Herbes de Provence": "Прованские травы", "Italian Seasoning": "Итальянские травы",
    "Dried Basil": "Сушёный базилик", "Dried Thyme": "Сушёный тимьян",
    "Dried Oregano": "Сушёный орегано", "Dried Rosemary": "Сушёный розмарин",
    "Dried Sage": "Сушёный шалфей", "Dried Parsley": "Сушёная петрушка",
    "Dried Dill": "Сушёный укроп", "Dried Mint": "Сушёная мята",
    "Dried Tarragon": "Сушёный эстрагон", "Dried Marjoram": "Сушёный майоран",
    "Juniper Berries": "Ягоды можжевельника", "Mace": "Мацис",
    "Asafoetida": "Асафетида", "Ajwain": "Айован", "Amchur": "Амчур",
    "Annatto": "Аннато", "Epazote": "Эпазот", "Grains of Paradise": "Зёрна рая",
    "Long Pepper": "Длинный перец", "Sichuan Pepper": "Сычуаньский перец",

    # Sauces & Condiments
    "Salt": "Соль", "Sugar": "Сахар", "Honey": "Мёд",
    "Vinegar": "Уксус", "Soy Sauce": "Соевый соус",
    "Fish Sauce": "Рыбный соус", "Oyster Sauce": "Устричный соус",
    "Hot Sauce": "Острый соус", "Worcestershire Sauce": "Вустерский соус",
    "Tabasco": "Табаско", "Sriracha": "Шрирача", "Hoisin Sauce": "Хойсин",
    "Teriyaki Sauce": "Терияки", "Barbecue Sauce": "Соус барбекю",
    "Tomato Sauce": "Томатный соус", "Tomato Paste": "Томатная паста",
    "Ketchup": "Кетчуп", "Mayonnaise": "Майонез", "Mustard": "Горчица",
    "Dijon Mustard": "Дижонская горчица", "Whole Grain Mustard": "Зернистая горчица",
    "Horseradish Sauce": "Соус из хрена", "Tahini": "Тахини",
    "Hummus": "Хумус", "Pesto": "Песто", "Aioli": "Айоли",
    "Tzatziki": "Цацики", "Chimichurri": "Чимичурри",
    "Romesco": "Ромеско", "Salsa Verde": "Сальса верде",
    "Beurre Blanc": "Белое масло", "Hollandaise": "Голландский соус",
    "Bechamel": "Бешамель", "Veloute": "Велюте",
    "Espagnole": "Эспаньоль", "Demi-Glace": "Деми-гляс",
    "Apple Cider Vinegar": "Яблочный уксус", "Balsamic Vinegar": "Бальзамический уксус",
    "Red Wine Vinegar": "Красный винный уксус", "White Wine Vinegar": "Белый винный уксус",
    "Rice Vinegar": "Рисовый уксус", "Malt Vinegar": "Солодовый уксус",
    "Sherry Vinegar": "Хересный уксус", "Champagne Vinegar": "Шампанский уксус",
    "Ponzu": "Понзу", "Nam Pla": "Рыбный соус", "Mirin": "Мирин",
    "Sake": "Саке", "Shaoxing Wine": "Вино Шаосин", "Mango Chutney": "Чатни из манго",
    "Tamarind Paste": "Пасте из тамаринда", "Coconut Aminos": "Кокосовые аминокислоты",
    "Liquid Aminos": "Жидкие аминокислоты", "Coconut Cream": "Кокосовые сливки",
    "Coconut Milk": "Кокосовое молоко",

    # Bakery
    "White Bread": "Белый хлеб", "Whole Wheat Bread": "Цельнозерновой хлеб",
    "Sourdough Bread": "Хлеб на закваске", "Rye Bread": "Ржаной хлеб",
    "Baguette": "Багет", "Ciabatta": "Чиабатта", "Focaccia": "Фокачча",
    "Pita Bread": "Питта", "Lavash": "Лаваш", "Naan": "Наан",
    "Croissant": "Круассан", "Brioche": "Бриошь", "Challah": "Хала",
    "Pretzel": "Крендель", "Bagel": "Бублик", "English Muffin": "Английский маффин",
    "Tortilla": "Тортилья", "Crumpet": "Крампет",
    "Yeast": "Дрожжи", "Baking Powder": "Разрыхлитель",
    "Baking Soda": "Сода пищевая", "Bread Crumbs": "Панировочные сухари",
    "Panko": "Панко", "Croutons": "Гренки",

    # Beverages
    "Water": "Вода", "Sparkling Water": "Газированная вода",
    "Coffee": "Кофе", "Espresso": "Эспрессо", "Green Tea": "Зелёный чай",
    "Black Tea": "Чёрный чай", "Herbal Tea": "Травяной чай",
    "Orange Juice": "Апельсиновый сок", "Apple Juice": "Яблочный сок",
    "Lemon Juice": "Лимонный сок", "Lime Juice": "Сок лайма",
    "Tomato Juice": "Томатный сок", "Carrot Juice": "Морковный сок",
    "Grape Juice": "Виноградный сок", "Cranberry Juice": "Клюквенный сок",
    "Pomegranate Juice": "Гранатовый сок", "Coconut Water": "Кокосовая вода",
    "Almond Milk": "Миндальное молоко", "Oat Milk": "Овсяное молоко",
    "Soy Milk": "Соевое молоко", "Rice Milk": "Рисовое молоко",
    "Cashew Milk": "Молоко кешью", "Hemp Milk": "Конопляное молоко",
    "Cocoa": "Какао", "Hot Chocolate": "Горячий шоколад",
    "Chicory": "Цикорий", "Kombucha": "Комбуча",
    "Kvass": "Квас", "Kompot": "Компот",

    # Sweets & Desserts
    "Chocolate": "Шоколад", "Dark Chocolate": "Тёмный шоколад",
    "Milk Chocolate": "Молочный шоколад", "White Chocolate": "Белый шоколад",
    "Cocoa Powder": "Какао-порошок", "Vanilla": "Ванилин",
    "Vanilla Extract": "Экстракт ванили", "Maple Syrup": "Кленовый сироп",
    "Agave Syrup": "Агавовый сироп", "Corn Syrup": "Кукурузный сироп",
    "Molasses": "Патока", "Brown Sugar": "Коричневый сахар",
    "Powdered Sugar": "Сахарная пудра", "Confectioners Sugar": "Сахарная пудра",
    "Gelatin": "Желатин", "Pectin": "Пектин", "Xanthan Gum": "Ксантановая камедь",
    "Corn Starch": "Кукурузный крахмал", "Potato Starch": "Картофельный крахмал",
    "Caramel": "Карамель", "Dulce de Leche": "Дульсе де лече",
    "Jam": "Джем", "Jelly": "Желе", "Marmalade": "Мармелад",
    "Peanut Butter": "Арахисовая паста", "Almond Butter": "Миндальная паста",
    "Nutella": "Нутелла", "Marzipan": "Марципан",
    "Nougat": "Нуга", "Praline": "Пралине",

    # Processed Meat
    "Bacon": "Бекон", "Ham": "Ветчина", "Prosciutto": "Прошутто",
    "Salami": "Салями", "Pepperoni": "Пепперони", "Sausage": "Колбаса",
    "Hot Dog": "Сосиска", "Chorizo": "Чоризо", "Mortadella": "Мортаделла",
    "Pancetta": "Панчетта", "Guanciale": "Гуанчале",
    "Lardons": "Лардоны", "Frankfurter": "Сосиска-франкфурт",
    "Bratwurst": "Брат-вурст", "Kielbasa": "Кильбаса", "Andouille": "Андуй",
    "Merguez": "Мергез", "Longaniza": "Лонганиза",
    "Pastrami": "Пастрами", "Corned Beef": "Корнед биф",
    "Bresaola": "Брезаола", "Lardo": "Лардо",
    "Coppa": "Коппа", "Capicola": "Капикола",
    "Speck": "Шпек", "Jambon": "Жамбон",
    "Serrano Ham": "Хамон серрано", "Iberico Ham": "Хамон иберико",
    "Jamon": "Хамон", "Black Forest Ham": "Чернолесская ветчина",

    # Poultry
    "Chicken": "Курица", "Turkey": "Индейка", "Duck": "Утка",
    "Goose": "Гусь", "Guinea Fowl": "Цесарка", "Pigeon": "Голубь",
    "Squab": "Молодой голубь", "Quail Meat": "Мясо перепела",
    "Pheasant Meat": "Мясо фазана", "Partridge": "Куропатка",
    "Grouse": "Тетерев", "Woodcock": "Вальдшнеп",
    "Chicken Stock": "Куриный бульон", "Chicken Breast Skin On": "Куриная грудка с кожей",
    "Chicken Legs": "Куриные ножки", "Chicken Quarters": "Куриные четверти",
    "Ground Turkey": "Фарш из индейки", "Turkey Bacon": "Бекон из индейки",
    "Duck Confit": "Конфи из утки", "Goose Liver": "Гусиная печень",
    "Foie Gras": "Фуа-гра",
}

# ─── Russian translations for categories of world_products entries ────────────
CATEGORY_RU = {
    "vegetables": "Овощи", "fruits": "Фрукты", "meat": "Мясо",
    "fish": "Рыба", "seafood": "Морепродукты", "dairy": "Молочные продукты",
    "eggs": "Яйца", "grains": "Крупы и мука", "nuts": "Орехи и семена",
    "legumes": "Бобовые", "oils": "Масла", "spices": "Специи",
    "sauces": "Соусы и приправы", "bakery": "Выпечка",
    "beverages": "Напитки", "sweets": "Сладости",
    "processed_meat": "Колбасные изделия", "poultry": "Птица",
}

def make_product(p):
    """Convert world_products entry to Supabase product row."""
    en_name = p["name"]
    ru_name = EN_RU.get(en_name, en_name)  # fallback to en name if no translation

    return {
        "id": str(uuid.uuid4()),
        "name": ru_name,  # primary name in Russian
        "names": {"ru": ru_name, "en": en_name},
        "category": p.get("category", "misc"),
        "unit": "g" if p.get("unit") in ("g", "gram", "гр", "г") else "kg",
        "calories": p.get("calories", 0),
        "protein": p.get("protein", 0),
        "fat": p.get("fat", 0),
        "carbs": p.get("carbs", 0),
    }

def fetch_existing_names():
    """Fetch all existing product names from Supabase.
    Returns (names_set, total_count)."""
    existing = set()
    total = 0
    offset = 0
    while True:
        path = f"/rest/v1/products?select=name,names&limit=1000&offset={offset}"
        req = urllib.request.Request(
            f"{SUPABASE_URL}{path}",
            headers={"apikey": API_KEY, "Authorization": f"Bearer {API_KEY}"}
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
        total += len(data)
        for p in data:
            existing.add(p["name"].lower().strip())
            if p.get("names"):
                if p["names"].get("en"): existing.add(p["names"]["en"].lower().strip())
                if p["names"].get("ru"): existing.add(p["names"]["ru"].lower().strip())
        if len(data) < 1000:
            break
        offset += 1000
    return existing, total

def insert_batch(products):
    """Insert a batch of products, ignoring duplicates."""
    body = json.dumps(products).encode("utf-8")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/products",
        data=body,
        headers={
            "apikey": API_KEY,
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            # resolution=ignore-duplicates пропускает конфликты по уникальным ключам
            "Prefer": "return=minimal,resolution=ignore-duplicates",
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        print(f"  ERROR {e.code}: {err[:200]}")
        return e.code

def main():
    print("=== Загрузка продуктов в Supabase ===")
    print(f"Используем ключ: {'SERVICE_ROLE' if SERVICE_KEY else 'ANON (может не сработать из-за RLS)'}")
    print()

    print("1. Загружаем существующие продукты...")
    existing, current_total = fetch_existing_names()
    print(f"   Найдено в базе: {current_total} продуктов")

    print("2. Читаем источники продуктов...")
    # Основной список (английские названия)
    with open("world_products.json") as f:
        world = json.load(f)
    print(f"   world_products.json: {len(world)}")

    import os
    extra = []
    for fname in ["extra_products.json", "extra_products2.json", "extra_products3.json", "extra_products4.json", "extra_products5.json", "extra_products6.json", "extra_products_last.json", "extra_products_final.json"]:
        if os.path.exists(fname):
            with open(fname, encoding="utf-8") as f:
                part = json.load(f)
            extra.extend(part)
            print(f"   {fname}: {len(part)}")

    print("3. Фильтруем дубликаты...")
    new_products = []
    seen_in_batch = set()

    # Обрабатываем world_products (en names)
    for p in world:
        en = p["name"].lower().strip()
        ru = EN_RU.get(p["name"], p["name"]).lower().strip()
        if en in existing or ru in existing:
            continue
        if ru in seen_in_batch or en in seen_in_batch:
            continue
        seen_in_batch.add(ru)
        seen_in_batch.add(en)
        new_products.append(make_product(p))

    # Обрабатываем extra_products (ru names with en translations)
    for p in extra:
        ru = p["name"].lower().strip()
        en = p.get("en", p["name"]).lower().strip()
        if ru in existing or en in existing:
            continue
        if ru in seen_in_batch or en in seen_in_batch:
            continue
        seen_in_batch.add(ru)
        seen_in_batch.add(en)
        en_orig = p.get("en", p["name"])
        ru_orig = p["name"]
        new_products.append({
            "id": str(uuid.uuid4()),
            "name": ru_orig,
            "names": {"ru": ru_orig, "en": en_orig},
            "category": p.get("category", "misc"),
            "unit": "g" if p.get("unit") in ("g", "gram", "гр", "г") else "kg",
            "calories": p.get("calories", 0),
            "protein": p.get("protein", 0),
            "fat": p.get("fat", 0),
            "carbs": p.get("carbs", 0),
        })

    print(f"   Новых для добавления: {len(new_products)}")

    # Limit to what's needed to reach TARGET_TOTAL
    need = TARGET_TOTAL - current_total
    if need <= 0:
        print(f"   Уже {current_total} продуктов — цель достигнута!")
        return

    to_insert = new_products[:need]
    print(f"   Будем добавлять: {len(to_insert)} продуктов")
    print()

    print("4. Удаляем тестовую запись если есть...")
    try:
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/products?id=eq.00000000-0000-0000-0000-000000000001",
            headers={"apikey": API_KEY, "Authorization": f"Bearer {API_KEY}"},
            method="DELETE"
        )
        urllib.request.urlopen(req)
    except Exception:
        pass

    print("5. Загружаем пачками...")
    total_inserted = 0
    failed_batches = 0
    for i in range(0, len(to_insert), BATCH_SIZE):
        batch = to_insert[i:i + BATCH_SIZE]
        status = insert_batch(batch)
        if status in (200, 201):
            total_inserted += len(batch)
            done = i + len(batch)
            print(f"   [{done}/{len(to_insert)}] OK (+{len(batch)} → итого ~{current_total + total_inserted})")
        else:
            failed_batches += 1
            print(f"   [{i+len(batch)}/{len(to_insert)}] FAILED status={status}")
            if failed_batches >= 3:
                print("   Слишком много ошибок — останавливаемся")
                break
        time.sleep(0.15)

    print()
    print(f"=== Готово: добавлено {total_inserted} продуктов ===")
    print(f"Итого в базе: ~{current_total + total_inserted}")

if __name__ == "__main__":
    main()
