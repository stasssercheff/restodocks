require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

// Используем значения из .env файла
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('❌ SUPABASE_URL или SUPABASE_ANON_KEY не заданы');
  process.exit(1);
}

console.log('🔄 Проверяем подключение к Supabase...');

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function testConnection() {
  try {
    // Проверяем подключение к establishments
    const { data: establishments, error: establishmentsError } = await supabase
      .from('establishments')
      .select('id, name, pin_code')
      .limit(1);

    if (establishmentsError) {
      console.error('❌ Ошибка при подключении к establishments:', establishmentsError.message);
      return;
    }

    console.log('✅ Подключение к establishments успешно');
    console.log('📊 Найдено заведений:', establishments?.length || 0);

    // Проверяем структуру employees
    const { data: employees, error: employeesError } = await supabase
      .from('employees')
      .select('*')
      .limit(1);

    if (employeesError) {
      console.error('❌ Ошибка при подключении к employees:', employeesError.message);
      console.log('🔍 Попробуем посмотреть структуру таблицы...');

      // Попробуем получить информацию о колонках
      const { data: columns, error: columnsError } = await supabase
        .rpc('get_table_columns', { table_name: 'employees' });

      if (columnsError) {
        console.log('❌ Не удалось получить информацию о колонках');
        return;
      }

      console.log('📋 Колонки в employees:', columns);
      return;
    }

    console.log('✅ Подключение к employees успешно');
    console.log('👥 Найдено сотрудников:', employees?.length || 0);

    if (employees && employees.length > 0) {
      console.log('📋 Структура первого сотрудника:', Object.keys(employees[0]));
      console.log('👤 Данные сотрудника:', {
        id: employees[0].id,
        email: employees[0].email,
        full_name: employees[0].full_name,
        roles: employees[0].roles,
        is_active: employees[0].is_active,
        establishment_id: employees[0].establishment_id
      });

      // Проверим заведение
      const establishmentId = employees[0].establishment_id;
      const { data: est, error: estError } = await supabase
        .from('establishments')
        .select('id, name, pin_code, owner_id')
        .eq('id', establishmentId)
        .single();

      if (estError) {
        console.error('❌ Ошибка при получении заведения:', estError.message);
      } else {
        console.log('🏢 Данные заведения:', {
          id: est.id,
          name: est.name,
          pin_code: est.pin_code,
          owner_id: est.owner_id
        });
      }
    }

    console.log('🎉 Все проверки прошли успешно! База данных доступна.');

  } catch (error) {
    console.error('❌ Критическая ошибка:', error.message);
  }
}

testConnection();