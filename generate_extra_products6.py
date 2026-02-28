#!/usr/bin/env python3
"""
Шестая финальная партия: ~320 уникальных продуктов.
Всё что ещё не было добавлено.
"""
import json

EXTRA6 = [
    # ─── Мясные изделия ─────────────────────────────────────────────────────
    {"name": "Брезаола итальянская вяленая говядина", "en": "Bresaola Air Dried Beef Italian", "category": "processed_meat", "unit": "g", "calories": 175, "protein": 32.0, "fat": 3.5, "carbs": 0.3},
    {"name": "Андуйет французская колбаска", "en": "Andouillette French Chitterling", "category": "processed_meat", "unit": "g", "calories": 250, "protein": 11.5, "fat": 22.0, "carbs": 1.0},
    {"name": "Удлинённая краковская", "en": "Krakow Dry Cured Sausage", "category": "processed_meat", "unit": "g", "calories": 348, "protein": 16.2, "fat": 30.8, "carbs": 1.4},
    {"name": "Колбаса охотничья нежирная", "en": "Lean Hunters Dry Sausage", "category": "processed_meat", "unit": "g", "calories": 290, "protein": 20.0, "fat": 22.5, "carbs": 1.5},
    {"name": "Ливерная колбаса", "en": "Liverwurst Liver Sausage", "category": "processed_meat", "unit": "g", "calories": 326, "protein": 14.5, "fat": 28.5, "carbs": 2.8},
    {"name": "Кровяная колбаса", "en": "Black Pudding Blood Sausage", "category": "processed_meat", "unit": "g", "calories": 379, "protein": 14.0, "fat": 35.0, "carbs": 3.5},
    {"name": "Зельц холодец мясной", "en": "Head Cheese Sulzwurst", "category": "processed_meat", "unit": "g", "calories": 140, "protein": 14.0, "fat": 9.0, "carbs": 0.5},
    {"name": "Студень из говяжьих ножек", "en": "Beef Feet Aspic Studzen", "category": "processed_meat", "unit": "g", "calories": 130, "protein": 18.0, "fat": 6.5, "carbs": 0.0},
    {"name": "Куриная колбаса чёрная перец", "en": "Black Pepper Chicken Sausage", "category": "processed_meat", "unit": "g", "calories": 195, "protein": 17.5, "fat": 12.5, "carbs": 2.0},
    {"name": "Говяжья колбаса мерге", "en": "Merguez Spicy Beef Sausage", "category": "processed_meat", "unit": "g", "calories": 285, "protein": 18.5, "fat": 23.0, "carbs": 0.5},
    {"name": "Утиный паштет", "en": "Duck Confit Rillettes Pate", "category": "processed_meat", "unit": "g", "calories": 400, "protein": 18.0, "fat": 35.0, "carbs": 1.0},
    {"name": "Паштет из кролика", "en": "Rabbit Terrine Pate", "category": "processed_meat", "unit": "g", "calories": 230, "protein": 16.5, "fat": 17.5, "carbs": 2.0},

    # ─── Экзотические фрукты ─────────────────────────────────────────────────
    {"name": "Мамей сапота", "en": "Mamey Sapote Tropical", "category": "fruits", "unit": "g", "calories": 124, "protein": 1.4, "fat": 0.4, "carbs": 32.0},
    {"name": "Чёрная сапота", "en": "Black Sapote Chocolate Pudding", "category": "fruits", "unit": "g", "calories": 130, "protein": 1.0, "fat": 0.1, "carbs": 34.0},
    {"name": "Белая сапота", "en": "White Zapote Mexican Apple", "category": "fruits", "unit": "g", "calories": 76, "protein": 1.5, "fat": 0.2, "carbs": 18.4},
    {"name": "Канистель тофи-яблоко", "en": "Canistel Eggfruit Toffee", "category": "fruits", "unit": "g", "calories": 138, "protein": 1.7, "fat": 0.2, "carbs": 35.0},
    {"name": "Лукума перуанская", "en": "Lucuma Peruvian Gold", "category": "fruits", "unit": "g", "calories": 329, "protein": 4.0, "fat": 2.4, "carbs": 86.5},
    {"name": "Купуасу амазонский", "en": "Cupuacu Amazon Fruit", "category": "fruits", "unit": "g", "calories": 50, "protein": 1.2, "fat": 0.5, "carbs": 12.1},
    {"name": "Умари пёстрый плод", "en": "Umari Poraqueiba Fruit", "category": "fruits", "unit": "g", "calories": 140, "protein": 2.0, "fat": 10.0, "carbs": 15.0},
    {"name": "Сальведор пузырчатый", "en": "Salak Snake Fruit", "category": "fruits", "unit": "g", "calories": 82, "protein": 0.4, "fat": 0.4, "carbs": 20.9},
    {"name": "Лонган красный", "en": "Red Longan Dimocarpus", "category": "fruits", "unit": "g", "calories": 60, "protein": 1.3, "fat": 0.1, "carbs": 15.1},
    {"name": "Личи чёрный", "en": "Black Lychee Rose Scented", "category": "fruits", "unit": "g", "calories": 66, "protein": 0.8, "fat": 0.4, "carbs": 16.5},
    {"name": "Гуанабана саурсоп", "en": "Soursop Guanabana Graviola", "category": "fruits", "unit": "g", "calories": 66, "protein": 1.0, "fat": 0.3, "carbs": 16.8},
    {"name": "Нанс ягода жёлтая", "en": "Nance Nancite Yellow Berry", "category": "fruits", "unit": "g", "calories": 67, "protein": 0.4, "fat": 1.0, "carbs": 15.8},
    {"name": "Сурсоп листья чай", "en": "Soursop Leaf Herbal Tea", "category": "beverages", "unit": "g", "calories": 0, "protein": 0.0, "fat": 0.0, "carbs": 0.0},
    {"name": "Касимирова нежность", "en": "Casimiroa White Sapote", "category": "fruits", "unit": "g", "calories": 76, "protein": 1.5, "fat": 0.2, "carbs": 18.4},

    # ─── Овощи редкие ────────────────────────────────────────────────────────
    {"name": "Бамия красная", "en": "Red Burgundy Okra", "category": "vegetables", "unit": "g", "calories": 33, "protein": 1.9, "fat": 0.2, "carbs": 7.5},
    {"name": "Горький миндаль", "en": "Bitter Almond Apricot Kernel", "category": "nuts", "unit": "g", "calories": 560, "protein": 25.0, "fat": 45.0, "carbs": 20.0},
    {"name": "Фиолетовый ямс", "en": "Ube Purple Yam", "category": "vegetables", "unit": "g", "calories": 140, "protein": 1.5, "fat": 0.1, "carbs": 31.3},
    {"name": "Эдамаме стручки варёные", "en": "Boiled Edamame in Pod", "category": "legumes", "unit": "g", "calories": 122, "protein": 11.9, "fat": 5.2, "carbs": 8.9},
    {"name": "Пурпурная морковь", "en": "Purple Haze Carrot", "category": "vegetables", "unit": "g", "calories": 41, "protein": 0.9, "fat": 0.2, "carbs": 9.6},
    {"name": "Радужная свёкла", "en": "Rainbow Beet Chioggia", "category": "vegetables", "unit": "g", "calories": 43, "protein": 1.6, "fat": 0.2, "carbs": 9.6},
    {"name": "Мини-кукуруза початки", "en": "Baby Corn Mini Cob", "category": "vegetables", "unit": "g", "calories": 26, "protein": 2.5, "fat": 0.2, "carbs": 5.4},
    {"name": "Рукола дикая", "en": "Wild Rocket Arugula", "category": "vegetables", "unit": "g", "calories": 25, "protein": 2.6, "fat": 0.7, "carbs": 2.9},
    {"name": "Маш ростки пророщенные", "en": "Sprouted Mung Bean Shoots", "category": "vegetables", "unit": "g", "calories": 30, "protein": 3.0, "fat": 0.2, "carbs": 5.9},
    {"name": "Лук медвежий дикий", "en": "Wild Garlic Ramps Allium", "category": "vegetables", "unit": "g", "calories": 29, "protein": 1.9, "fat": 0.1, "carbs": 7.0},
    {"name": "Крапива листья молодые", "en": "Young Stinging Nettle Leaves", "category": "vegetables", "unit": "g", "calories": 42, "protein": 2.7, "fat": 0.1, "carbs": 7.5},
    {"name": "Одуванчик листья", "en": "Dandelion Greens Leaves", "category": "vegetables", "unit": "g", "calories": 45, "protein": 2.7, "fat": 0.7, "carbs": 9.2},
    {"name": "Щавель кислый листья", "en": "Sorrel Sour Dock Leaves", "category": "vegetables", "unit": "g", "calories": 22, "protein": 2.0, "fat": 0.7, "carbs": 3.2},
    {"name": "Мокрица сурепка", "en": "Chickweed Stellaria Spring", "category": "vegetables", "unit": "g", "calories": 19, "protein": 1.8, "fat": 0.5, "carbs": 3.6},
    {"name": "Черемша медвежий лук", "en": "Bear Garlic Ramsons Leaves", "category": "vegetables", "unit": "g", "calories": 29, "protein": 1.9, "fat": 0.1, "carbs": 7.0},
    {"name": "Портулак огородный", "en": "Garden Purslane Portulaca", "category": "vegetables", "unit": "g", "calories": 16, "protein": 1.3, "fat": 0.4, "carbs": 3.4},
    {"name": "Пастушья сумка", "en": "Shepherd's Purse Capsella", "category": "vegetables", "unit": "g", "calories": 35, "protein": 3.5, "fat": 0.5, "carbs": 6.0},
    {"name": "Конский щавель листья", "en": "Patience Dock Rumex", "category": "vegetables", "unit": "g", "calories": 22, "protein": 2.0, "fat": 0.7, "carbs": 3.2},
    {"name": "Кислица оксалис", "en": "Oxalis Wood Sorrel Herb", "category": "vegetables", "unit": "g", "calories": 29, "protein": 2.0, "fat": 0.5, "carbs": 5.3},

    # ─── Кулинарные добавки ───────────────────────────────────────────────────
    {"name": "Желтый сахар турбинадо", "en": "Turbinado Raw Cane Sugar", "category": "sweets", "unit": "g", "calories": 377, "protein": 0.0, "fat": 0.0, "carbs": 99.8},
    {"name": "Сахар мусковадо тёмный", "en": "Dark Muscovado Cane Sugar", "category": "sweets", "unit": "g", "calories": 360, "protein": 0.5, "fat": 0.0, "carbs": 95.0},
    {"name": "Дата сахарная финиковый", "en": "Date Sugar Dried Fruit", "category": "sweets", "unit": "g", "calories": 325, "protein": 2.5, "fat": 0.0, "carbs": 85.0},
    {"name": "Сахарный сироп из тростника", "en": "Pure Cane Simple Syrup", "category": "sweets", "unit": "g", "calories": 277, "protein": 0.0, "fat": 0.0, "carbs": 70.0},
    {"name": "Сироп топинамбура", "en": "Jerusalem Artichoke Syrup", "category": "sweets", "unit": "g", "calories": 240, "protein": 0.0, "fat": 0.0, "carbs": 60.0},
    {"name": "Сукралоза подсластитель", "en": "Sucralose Artificial Sweetener", "category": "sweets", "unit": "g", "calories": 0, "protein": 0.0, "fat": 0.0, "carbs": 0.0},
    {"name": "Ацесульфам калий", "en": "Acesulfame Potassium E950", "category": "sweets", "unit": "g", "calories": 0, "protein": 0.0, "fat": 0.0, "carbs": 0.0},
    {"name": "Аспартам подсластитель", "en": "Aspartame Low Cal Sweetener", "category": "sweets", "unit": "g", "calories": 4, "protein": 0.0, "fat": 0.0, "carbs": 0.0},

    # ─── Сыры дополнительно ──────────────────────────────────────────────────
    {"name": "Сыр лимбургский", "en": "Limburger Washed Rind German", "category": "dairy", "unit": "g", "calories": 327, "protein": 20.1, "fat": 27.3, "carbs": 0.5},
    {"name": "Сыр тет де муан", "en": "Tete de Moine Swiss Monk", "category": "dairy", "unit": "g", "calories": 389, "protein": 26.0, "fat": 31.5, "carbs": 0.1},
    {"name": "Сыр ярлсберг норвежский", "en": "Jarlsberg Norwegian Swiss Style", "category": "dairy", "unit": "g", "calories": 363, "protein": 27.0, "fat": 27.0, "carbs": 0.5},
    {"name": "Сыр дам блю датский", "en": "Danish Danbo Blue Cheese", "category": "dairy", "unit": "g", "calories": 350, "protein": 22.5, "fat": 28.0, "carbs": 1.5},
    {"name": "Сыр фонтал альпийский", "en": "Fontal Alpine Pressed Cheese", "category": "dairy", "unit": "g", "calories": 342, "protein": 23.5, "fat": 27.0, "carbs": 0.5},
    {"name": "Сыр пьяная корова", "en": "Ubriaco Drunken Cheese Italian", "category": "dairy", "unit": "g", "calories": 380, "protein": 27.0, "fat": 30.5, "carbs": 0.0},
    {"name": "Сыр гротто грюйер", "en": "Grotto Swiss Cave Gruyere", "category": "dairy", "unit": "g", "calories": 413, "protein": 29.0, "fat": 32.5, "carbs": 0.4},
    {"name": "Сыр ромадур", "en": "Romadur Austrian Soft Cheese", "category": "dairy", "unit": "g", "calories": 240, "protein": 19.5, "fat": 17.5, "carbs": 1.0},
    {"name": "Сыр мюнстер французский", "en": "French Alsace Munster AOC", "category": "dairy", "unit": "g", "calories": 313, "protein": 21.0, "fat": 24.9, "carbs": 0.2},
    {"name": "Сыр кесо бланко", "en": "Queso Blanco Latin Fresh", "category": "dairy", "unit": "g", "calories": 260, "protein": 16.0, "fat": 20.0, "carbs": 3.0},
    {"name": "Сыр котиха крошащийся", "en": "Cotija Aged Crumbling Mexican", "category": "dairy", "unit": "g", "calories": 375, "protein": 23.5, "fat": 30.0, "carbs": 2.0},
    {"name": "Рикотта запечённая", "en": "Baked Ricotta Ricotta Infornata", "category": "dairy", "unit": "g", "calories": 200, "protein": 15.0, "fat": 13.5, "carbs": 4.5},
    {"name": "Творог нежирный 0.5%", "en": "Low Fat Cottage Cheese 0.5%", "category": "dairy", "unit": "g", "calories": 79, "protein": 16.7, "fat": 0.5, "carbs": 1.8},

    # ─── Выпечка профессиональная ─────────────────────────────────────────────
    {"name": "Тесто фило", "en": "Filo Phyllo Pastry Sheets", "category": "bakery", "unit": "g", "calories": 310, "protein": 8.5, "fat": 5.0, "carbs": 60.0},
    {"name": "Тесто катаифи", "en": "Kataifi Shredded Filo Dough", "category": "bakery", "unit": "g", "calories": 310, "protein": 8.5, "fat": 5.0, "carbs": 60.0},
    {"name": "Тесто для лазаньи свежее", "en": "Fresh Pasta Lasagna Sheets", "category": "bakery", "unit": "g", "calories": 131, "protein": 5.0, "fat": 1.5, "carbs": 24.5},
    {"name": "Тесто для гёзы", "en": "Gyoza Dumpling Wrapper", "category": "bakery", "unit": "g", "calories": 295, "protein": 8.5, "fat": 0.7, "carbs": 62.0},
    {"name": "Тесто для бау китайские булочки", "en": "Bao Bun Steamed Dough", "category": "bakery", "unit": "g", "calories": 260, "protein": 7.0, "fat": 4.5, "carbs": 50.0},
    {"name": "Тесто вытяжное штрудель", "en": "Strudel Pulling Dough", "category": "bakery", "unit": "g", "calories": 280, "protein": 7.5, "fat": 2.5, "carbs": 57.0},
    {"name": "Тесто для пахлавы", "en": "Baklava Pastry Filo", "category": "bakery", "unit": "g", "calories": 310, "protein": 8.5, "fat": 5.0, "carbs": 60.0},
    {"name": "Хлеб баттерфляй горчичный", "en": "Mustard Butterfly Bread Roll", "category": "bakery", "unit": "g", "calories": 270, "protein": 8.5, "fat": 4.0, "carbs": 50.5},
    {"name": "Сухари ржаные крупные", "en": "Large Rye Bread Croutons", "category": "bakery", "unit": "g", "calories": 330, "protein": 9.5, "fat": 2.5, "carbs": 67.0},
    {"name": "Кукурузный хлеб джонникейк", "en": "Cornbread Johnnycake", "category": "bakery", "unit": "g", "calories": 350, "protein": 7.5, "fat": 12.0, "carbs": 54.0},
    {"name": "Хлеб наан чесночный", "en": "Garlic Naan Flatbread", "category": "bakery", "unit": "g", "calories": 320, "protein": 9.5, "fat": 8.5, "carbs": 52.0},
    {"name": "Питта цельнозерновая", "en": "Whole Wheat Pita Bread", "category": "bakery", "unit": "g", "calories": 265, "protein": 9.5, "fat": 1.5, "carbs": 54.0},
    {"name": "Инжир листы инджера", "en": "Injera Ethiopian Sponge Bread", "category": "bakery", "unit": "g", "calories": 90, "protein": 3.5, "fat": 0.6, "carbs": 18.5},

    # ─── Приправы и смеси ─────────────────────────────────────────────────────
    {"name": "Смесь для маринада барбекю", "en": "Dry BBQ Rub Mix Seasoning", "category": "spices", "unit": "g", "calories": 290, "protein": 5.0, "fat": 4.5, "carbs": 60.0},
    {"name": "Смесь приправ жаркое", "en": "Roast Meat Herb Mix", "category": "spices", "unit": "g", "calories": 280, "protein": 8.0, "fat": 7.0, "carbs": 52.0},
    {"name": "Смесь специй ягнёнок", "en": "Lamb Herb Spice Rub", "category": "spices", "unit": "g", "calories": 275, "protein": 7.5, "fat": 8.5, "carbs": 50.0},
    {"name": "Смесь специй птица", "en": "Poultry Seasoning Herb Blend", "category": "spices", "unit": "g", "calories": 285, "protein": 8.5, "fat": 7.0, "carbs": 53.0},
    {"name": "Смесь специй рыба морепродукты", "en": "Seafood Old Bay Seasoning", "category": "spices", "unit": "g", "calories": 195, "protein": 6.0, "fat": 6.0, "carbs": 36.5},
    {"name": "Смесь карри мадрасский", "en": "Madras Curry Powder Blend", "category": "spices", "unit": "g", "calories": 344, "protein": 14.3, "fat": 14.6, "carbs": 55.8},
    {"name": "Карри тайский жёлтый", "en": "Thai Yellow Curry Powder", "category": "spices", "unit": "g", "calories": 344, "protein": 14.3, "fat": 14.6, "carbs": 55.8},
    {"name": "Смесь спесий дукка египетская", "en": "Dukkah Egyptian Nut Blend", "category": "spices", "unit": "g", "calories": 450, "protein": 18.0, "fat": 38.0, "carbs": 20.0},
    {"name": "Чимичурри аргентинский", "en": "Argentine Chimichurri Herb", "category": "sauces", "unit": "g", "calories": 112, "protein": 1.5, "fat": 10.5, "carbs": 5.0},
    {"name": "Соус перигурдин трюфельный", "en": "Perigueux Truffle Sauce", "category": "sauces", "unit": "g", "calories": 75, "protein": 3.0, "fat": 4.5, "carbs": 6.5},
    {"name": "Перец хлопья гочугару", "en": "Korean Gochugaru Red Pepper", "category": "spices", "unit": "g", "calories": 282, "protein": 12.0, "fat": 12.0, "carbs": 49.0},
    {"name": "Перец чипотле молотый", "en": "Ground Chipotle Pepper Powder", "category": "spices", "unit": "g", "calories": 282, "protein": 12.0, "fat": 14.3, "carbs": 49.7},
    {"name": "Смесь прованских трав", "en": "Herbes de Provence French Mix", "category": "spices", "unit": "g", "calories": 268, "protein": 9.0, "fat": 6.5, "carbs": 56.0},
    {"name": "Смесь итальянских трав", "en": "Italian Herbs Dried Mix", "category": "spices", "unit": "g", "calories": 265, "protein": 9.0, "fat": 5.5, "carbs": 56.0},
    {"name": "Букет гарни сухой", "en": "Bouquet Garni Dried Sachet", "category": "spices", "unit": "g", "calories": 260, "protein": 8.0, "fat": 5.0, "carbs": 57.0},
    {"name": "Смесь специй для глинтвейна", "en": "Mulled Wine Spice Mix", "category": "spices", "unit": "g", "calories": 280, "protein": 6.5, "fat": 7.0, "carbs": 58.0},

    # ─── Орехи особые ───────────────────────────────────────────────────────
    {"name": "Орех пили", "en": "Pili Nut Filipino", "category": "nuts", "unit": "g", "calories": 719, "protein": 10.8, "fat": 79.6, "carbs": 3.9},
    {"name": "Орех сапукайя", "en": "Paradise Sapucaia Nut", "category": "nuts", "unit": "g", "calories": 656, "protein": 14.3, "fat": 66.4, "carbs": 12.3},
    {"name": "Орех ингва", "en": "Inga Edulis Ice Cream Bean", "category": "nuts", "unit": "g", "calories": 95, "protein": 1.2, "fat": 0.2, "carbs": 22.9},
    {"name": "Кокосовый сахар с пальмы", "en": "Coconut Toddy Palm Sugar", "category": "sweets", "unit": "g", "calories": 375, "protein": 0.0, "fat": 0.0, "carbs": 97.0},
    {"name": "Паста урбеч из конопли", "en": "Hemp Seed Urbech Raw Paste", "category": "nuts", "unit": "g", "calories": 553, "protein": 31.6, "fat": 48.7, "carbs": 8.7},
    {"name": "Урбеч из чёрного кунжута", "en": "Black Sesame Seed Tahini", "category": "nuts", "unit": "g", "calories": 565, "protein": 17.7, "fat": 48.7, "carbs": 23.5},
    {"name": "Каштан водяной хрустящий", "en": "Asian Water Chestnut Crispy", "category": "nuts", "unit": "g", "calories": 97, "protein": 1.4, "fat": 0.1, "carbs": 23.9},
    {"name": "Тигровые орешки чуфа", "en": "Tiger Nut Chufa Earth Almond", "category": "nuts", "unit": "g", "calories": 455, "protein": 5.0, "fat": 24.8, "carbs": 59.5},

    # ─── Соусы особые ───────────────────────────────────────────────────────
    {"name": "Соус сюпрем курица", "en": "Supreme Cream Chicken Sauce", "category": "sauces", "unit": "g", "calories": 95, "protein": 3.5, "fat": 7.5, "carbs": 4.5},
    {"name": "Соус биск омар", "en": "Lobster Bisque Sauce", "category": "sauces", "unit": "g", "calories": 145, "protein": 5.5, "fat": 9.5, "carbs": 10.5},
    {"name": "Соус сан-репи морской", "en": "Sea Urchin Uni Sauce", "category": "sauces", "unit": "g", "calories": 120, "protein": 8.5, "fat": 7.5, "carbs": 5.5},
    {"name": "Соус дель яхни рагу", "en": "Turkish Yahni Stew Base", "category": "sauces", "unit": "g", "calories": 75, "protein": 2.5, "fat": 4.5, "carbs": 7.5},
    {"name": "Соус меласса гранатовый", "en": "Pomegranate Molasses Sauce", "category": "sauces", "unit": "g", "calories": 268, "protein": 1.0, "fat": 0.5, "carbs": 66.5},
    {"name": "Соус тамариндо", "en": "Tamarind Water Sauce Thai", "category": "sauces", "unit": "g", "calories": 95, "protein": 1.5, "fat": 0.3, "carbs": 24.5},
    {"name": "Соус манго острый", "en": "Spicy Mango Habanero Sauce", "category": "sauces", "unit": "g", "calories": 95, "protein": 0.8, "fat": 0.5, "carbs": 23.5},
    {"name": "Соус апельсин имбирь", "en": "Orange Ginger Asian Sauce", "category": "sauces", "unit": "g", "calories": 110, "protein": 1.5, "fat": 0.5, "carbs": 27.0},
    {"name": "Пасты гарум рыбный соус", "en": "Garum Roman Fish Sauce", "category": "sauces", "unit": "g", "calories": 35, "protein": 5.1, "fat": 0.0, "carbs": 3.6},
    {"name": "Вино Марсала для готовки", "en": "Marsala Cooking Wine Sicily", "category": "beverages", "unit": "g", "calories": 154, "protein": 0.1, "fat": 0.0, "carbs": 14.0},
    {"name": "Вино Порто для готовки", "en": "Ruby Port Wine Cooking", "category": "beverages", "unit": "g", "calories": 154, "protein": 0.1, "fat": 0.0, "carbs": 12.0},
    {"name": "Уксус умебоши японский", "en": "Japanese Ume Plum Vinegar", "category": "sauces", "unit": "g", "calories": 35, "protein": 0.4, "fat": 0.1, "carbs": 8.0},

    # ─── Молочные особые ─────────────────────────────────────────────────────
    {"name": "Айран кисломолочный напиток", "en": "Ayran Yogurt Drink Salted", "category": "dairy", "unit": "g", "calories": 30, "protein": 1.6, "fat": 1.5, "carbs": 2.5},
    {"name": "Ласси индийский йогурт", "en": "Indian Mango Lassi Yogurt", "category": "dairy", "unit": "g", "calories": 85, "protein": 3.5, "fat": 2.5, "carbs": 12.5},
    {"name": "Чайный напиток масала", "en": "Indian Chai Masala Spiced Tea", "category": "beverages", "unit": "g", "calories": 43, "protein": 1.5, "fat": 1.8, "carbs": 6.0},
    {"name": "Молочный коктейль ванильный", "en": "Vanilla Milkshake Classic", "category": "beverages", "unit": "g", "calories": 112, "protein": 3.5, "fat": 4.0, "carbs": 16.0},
    {"name": "Ряженка с топлёным маслом", "en": "Creamy Ryazhenka with Butter", "category": "dairy", "unit": "g", "calories": 92, "protein": 3.0, "fat": 6.5, "carbs": 5.5},
    {"name": "Молоко козье пастеризованное", "en": "Pasteurized Goat Milk", "category": "dairy", "unit": "g", "calories": 69, "protein": 3.6, "fat": 4.1, "carbs": 4.5},
    {"name": "Молоко овечье", "en": "Sheep Ewe Milk", "category": "dairy", "unit": "g", "calories": 108, "protein": 5.4, "fat": 7.0, "carbs": 5.4},
    {"name": "Молоко верблюжье", "en": "Camel Dromedary Milk", "category": "dairy", "unit": "g", "calories": 58, "protein": 3.1, "fat": 3.5, "carbs": 4.4},
    {"name": "Молоко буйволиное", "en": "Water Buffalo Milk", "category": "dairy", "unit": "g", "calories": 110, "protein": 4.5, "fat": 8.0, "carbs": 4.9},
    {"name": "Сыворотка протеиновая WPI", "en": "Whey Protein Isolate WPI", "category": "dairy", "unit": "g", "calories": 374, "protein": 90.0, "fat": 1.5, "carbs": 5.0},
    {"name": "Белок молочный казеин", "en": "Micellar Casein Milk Protein", "category": "dairy", "unit": "g", "calories": 364, "protein": 82.0, "fat": 2.0, "carbs": 9.0},

    # ─── Злаки особые ────────────────────────────────────────────────────────
    {"name": "Попкорн кукурузный", "en": "Popcorn Corn Kernels", "category": "grains", "unit": "g", "calories": 375, "protein": 12.9, "fat": 4.5, "carbs": 78.1},
    {"name": "Поп-рис хлопья воздушный", "en": "Puffed Rice Cereal Krispy", "category": "grains", "unit": "g", "calories": 381, "protein": 6.9, "fat": 0.8, "carbs": 88.1},
    {"name": "Воздушная пшеница", "en": "Puffed Wheat Cereal", "category": "grains", "unit": "g", "calories": 357, "protein": 13.7, "fat": 1.4, "carbs": 80.2},
    {"name": "Воздушная гречка", "en": "Puffed Buckwheat Grain", "category": "grains", "unit": "g", "calories": 350, "protein": 12.5, "fat": 3.5, "carbs": 75.0},
    {"name": "Воздушное пшено", "en": "Puffed Millet Grain", "category": "grains", "unit": "g", "calories": 348, "protein": 8.5, "fat": 4.2, "carbs": 75.0},
    {"name": "Воздушный амарант", "en": "Puffed Amaranth Grain", "category": "grains", "unit": "g", "calories": 371, "protein": 13.6, "fat": 7.0, "carbs": 65.3},
    {"name": "Овсянка стальной нарез", "en": "Steel Cut Irish Oats", "category": "grains", "unit": "g", "calories": 379, "protein": 13.5, "fat": 6.5, "carbs": 68.0},
    {"name": "Кукурузная крупа мелкого помола", "en": "Fine Ground Yellow Cornmeal", "category": "grains", "unit": "g", "calories": 366, "protein": 7.0, "fat": 3.4, "carbs": 78.0},
    {"name": "Пшеница булгур крупный", "en": "Coarse Bulgur Wheat", "category": "grains", "unit": "g", "calories": 342, "protein": 12.3, "fat": 1.3, "carbs": 75.9},
    {"name": "Перловка толчёная", "en": "Hulled Hulless Barley", "category": "grains", "unit": "g", "calories": 354, "protein": 12.5, "fat": 2.3, "carbs": 73.5},

    # ─── Мука особая ─────────────────────────────────────────────────────────
    {"name": "Мука чечевичная", "en": "Red Lentil Flour Protein", "category": "grains", "unit": "g", "calories": 352, "protein": 26.0, "fat": 1.1, "carbs": 59.0},
    {"name": "Мука кукурузная мелкая маса", "en": "Masa Harina Corn Flour", "category": "grains", "unit": "g", "calories": 361, "protein": 7.2, "fat": 3.7, "carbs": 72.0},
    {"name": "Мука горохового протеина", "en": "Yellow Pea Protein Flour", "category": "grains", "unit": "g", "calories": 355, "protein": 26.0, "fat": 1.0, "carbs": 58.0},
    {"name": "Мука инулиновая цикория", "en": "Chicory Root Inulin Flour", "category": "grains", "unit": "g", "calories": 150, "protein": 0.5, "fat": 0.2, "carbs": 70.0},
    {"name": "Мука из банана зелёного", "en": "Green Banana Flour", "category": "grains", "unit": "g", "calories": 354, "protein": 3.6, "fat": 0.7, "carbs": 88.3},
    {"name": "Мука из батата", "en": "Sweet Potato Flour Dried", "category": "grains", "unit": "g", "calories": 354, "protein": 5.0, "fat": 0.3, "carbs": 84.0},
    {"name": "Мука из маниока", "en": "Cassava Yuca Flour", "category": "grains", "unit": "g", "calories": 357, "protein": 0.2, "fat": 0.1, "carbs": 88.7},
    {"name": "Хлебная смесь без глютена", "en": "Gluten Free Bread Mix", "category": "grains", "unit": "g", "calories": 348, "protein": 4.5, "fat": 4.0, "carbs": 74.0},

    # ─── Бобовые ─────────────────────────────────────────────────────────────
    {"name": "Боб виндзорский", "en": "Windsor Broad Bean Fava", "category": "legumes", "unit": "g", "calories": 341, "protein": 26.1, "fat": 1.5, "carbs": 58.3},
    {"name": "Фасоль белая Лима", "en": "Butter Lima Bean White", "category": "legumes", "unit": "g", "calories": 338, "protein": 21.5, "fat": 0.7, "carbs": 63.4},
    {"name": "Фасоль пёстрая пинто", "en": "Pinto Bean Mottled", "category": "legumes", "unit": "g", "calories": 347, "protein": 21.4, "fat": 1.2, "carbs": 62.6},
    {"name": "Фасоль бурая боттон", "en": "Borlotti Roman Cranberry Bean", "category": "legumes", "unit": "g", "calories": 335, "protein": 23.0, "fat": 1.2, "carbs": 60.0},
    {"name": "Нут зелёный", "en": "Green Desi Chickpea", "category": "legumes", "unit": "g", "calories": 345, "protein": 18.8, "fat": 5.3, "carbs": 57.5},
    {"name": "Маш жёлтый дал", "en": "Yellow Mung Dal Split", "category": "legumes", "unit": "g", "calories": 347, "protein": 23.9, "fat": 1.2, "carbs": 62.6},
    {"name": "Чечевица итальянская умбрия", "en": "Umbria Castelluccio Lentils", "category": "legumes", "unit": "g", "calories": 116, "protein": 9.1, "fat": 0.4, "carbs": 20.1},
    {"name": "Горох нут мелкий индийский", "en": "Small Desi Indian Chickpea", "category": "legumes", "unit": "g", "calories": 360, "protein": 20.5, "fat": 5.9, "carbs": 60.1},
    {"name": "Фасоль адзуки японская", "en": "Adzuki Azuki Red Bean Japan", "category": "legumes", "unit": "g", "calories": 329, "protein": 19.9, "fat": 0.5, "carbs": 62.9},
    {"name": "Фасоль мотылёк", "en": "Winged Bean Psophocarpus", "category": "legumes", "unit": "g", "calories": 409, "protein": 29.7, "fat": 16.3, "carbs": 41.7},

    # ─── Полезные добавки ─────────────────────────────────────────────────────
    {"name": "Протеин горохового белка", "en": "Pea Protein Isolate Powder", "category": "legumes", "unit": "g", "calories": 357, "protein": 83.0, "fat": 6.0, "carbs": 3.0},
    {"name": "Протеин соевый изолят", "en": "Soy Protein Isolate Powder", "category": "legumes", "unit": "g", "calories": 374, "protein": 88.0, "fat": 1.5, "carbs": 3.0},
    {"name": "Протеин сывороточный WPC", "en": "Whey Protein Concentrate WPC", "category": "dairy", "unit": "g", "calories": 400, "protein": 75.0, "fat": 8.0, "carbs": 15.0},
    {"name": "Дрожжи пивные питательные", "en": "Nutritional Yeast Flakes", "category": "grains", "unit": "g", "calories": 325, "protein": 40.4, "fat": 7.6, "carbs": 41.2},
    {"name": "Порошок лукумы", "en": "Lucuma Fruit Powder", "category": "sweets", "unit": "g", "calories": 329, "protein": 4.0, "fat": 2.4, "carbs": 86.5},
    {"name": "Порошок маки перуанский", "en": "Maca Root Powder Peru", "category": "spices", "unit": "g", "calories": 325, "protein": 14.5, "fat": 2.2, "carbs": 71.4},
    {"name": "Порошок питахайи", "en": "Dragon Fruit Powder", "category": "sweets", "unit": "g", "calories": 219, "protein": 5.4, "fat": 1.7, "carbs": 54.4},
    {"name": "Порошок маракуйи", "en": "Passion Fruit Powder", "category": "sweets", "unit": "g", "calories": 352, "protein": 6.5, "fat": 1.5, "carbs": 88.0},
    {"name": "Порошок кокоса обезжиренный", "en": "Defatted Coconut Powder", "category": "nuts", "unit": "g", "calories": 280, "protein": 15.5, "fat": 5.0, "carbs": 55.0},
    {"name": "Порошок кешью", "en": "Cashew Nut Flour Ground", "category": "nuts", "unit": "g", "calories": 553, "protein": 15.3, "fat": 43.9, "carbs": 32.7},
    {"name": "Порошок куркумы биоактивный", "en": "Bioavailable Turmeric Curcumin", "category": "spices", "unit": "g", "calories": 354, "protein": 7.8, "fat": 9.9, "carbs": 64.9},
    {"name": "Порошок имбиря органический", "en": "Organic Ginger Root Powder", "category": "spices", "unit": "g", "calories": 335, "protein": 8.9, "fat": 4.2, "carbs": 71.6},
]

def main():
    print(f"Всего продуктов шестой партии: {len(EXTRA6)}")
    with open("extra_products6.json", "w", encoding="utf-8") as f:
        json.dump(EXTRA6, f, ensure_ascii=False, indent=2)
    print("Сохранено в extra_products6.json")

if __name__ == "__main__":
    main()
