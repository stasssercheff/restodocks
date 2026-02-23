// Генерация BCrypt хеша для пароля '1111!'
const bcrypt = require('bcrypt');

const password = '1111!';
const saltRounds = 10;

bcrypt.hash(password, saltRounds, function(err, hash) {
    if (err) {
        console.error('Error:', err);
    } else {
        console.log('Password:', password);
        console.log('BCrypt Hash:', hash);
        console.log('Use this hash in the migration script');
    }
});