require('dotenv').config();
const bcrypt = require('bcrypt');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('❌ SUPABASE_URL или SUPABASE_ANON_KEY не заданы');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function resetPassword() {
  const email = 'Stassser@gmail.com';
  const newPassword = '123456'; // Простой пароль для теста

  console.log(`🔄 Сбрасываем пароль для ${email}...`);

  try {
    // Генерируем хэш пароля
    const saltRounds = 12;
    const hashedPassword = await bcrypt.hash(newPassword, saltRounds);

    console.log('🔐 Сгенерирован хэш пароля');

    // Сначала найдем сотрудника
    const { data: employees, error: findError } = await supabase
      .from('employees')
      .select('id, email')
      .ilike('email', email.toLowerCase());

    if (findError) {
      console.error('❌ Ошибка при поиске сотрудника:', findError.message);
      return;
    }

    if (!employees || employees.length === 0) {
      console.error('❌ Сотрудник с таким email не найден');
      console.log('🔍 Попробуем найти всех сотрудников...');

      const { data: allEmployees, error: allError } = await supabase
        .from('employees')
        .select('id, email, full_name');

      if (allError) {
        console.error('❌ Ошибка при получении списка сотрудников:', allError.message);
      } else {
        console.log('👥 Все сотрудники в базе:', allEmployees);
      }
      return;
    }

    console.log('👤 Найден сотрудник:', employees[0]);

    // Обновляем пароль в базе данных
    const { data, error } = await supabase
      .from('employees')
      .update({ password_hash: hashedPassword })
      .eq('id', employees[0].id)
      .select();

    if (error) {
      console.error('❌ Ошибка при обновлении пароля:', error.message);
      return;
    }

    if (!data || data.length === 0) {
      console.error('❌ Не удалось обновить пароль - сотрудник не найден после обновления');
      return;
    }

    console.log('✅ Пароль успешно обновлен для сотрудника:', data[0].email);

    console.log('✅ Пароль успешно обновлен!');
    console.log('📧 Email:', email);
    console.log('🔑 Новый пароль:', newPassword);
    console.log('⚠️  Не забудьте изменить пароль после входа!');

  } catch (error) {
    console.error('❌ Критическая ошибка:', error.message);
  }
}

resetPassword();