const bcrypt = require('bcrypt');

async function generateHash() {
  const password = '123456';
  const saltRounds = 12;

  try {
    const hash = await bcrypt.hash(password, saltRounds);
    console.log('Пароль:', password);
    console.log('Хэш:', hash);
  } catch (error) {
    console.error('Ошибка:', error);
  }
}

generateHash();