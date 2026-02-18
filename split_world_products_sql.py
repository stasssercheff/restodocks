#!/usr/bin/env python3
"""
Split the large world_products_database.sql into smaller chunks for Supabase
"""

def split_sql_file(input_file, chunk_size=500):
    """Split SQL file into smaller chunks"""

    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Split by main sections
    parts = content.split('-- Clear existing data')

    if len(parts) != 2:
        print("Unexpected file structure")
        return

    header = "-- Clear existing data" + parts[1].split('INSERT INTO products')[0]
    products_section = "INSERT INTO products" + parts[1].split('INSERT INTO products')[1].split('INSERT INTO translations')[0]
    translations_section = "INSERT INTO translations" + parts[1].split('INSERT INTO translations')[1]

    # Create header file
    with open('01_clear_and_setup.sql', 'w', encoding='utf-8') as f:
        f.write(header.strip())

    # Split products into chunks
    products_lines = products_section.strip().split('\n')
    chunk_num = 1

    for i in range(0, len(products_lines), chunk_size):
        chunk = products_lines[i:i+chunk_size]
        filename = f'02_products_part_{chunk_num:02d}.sql'

        with open(filename, 'w', encoding='utf-8') as f:
            f.write('\n'.join(chunk))

        print(f"Created {filename} with {len(chunk)} lines")
        chunk_num += 1

    # Split translations into chunks
    translations_lines = translations_section.strip().split('\n')
    chunk_num = 1

    for i in range(0, len(translations_lines), chunk_size):
        chunk = translations_lines[i:i+chunk_size]
        filename = f'03_translations_part_{chunk_num:02d}.sql'

        with open(filename, 'w', encoding='utf-8') as f:
            f.write('\n'.join(chunk))

        print(f"Created {filename} with {len(chunk)} lines")
        chunk_num += 1

    print("\nSQL files split successfully!")
    print("Execute them in order: 01_clear_and_setup.sql, then 02_* files, then 03_* files")

if __name__ == "__main__":
    split_sql_file("world_products_database.sql")