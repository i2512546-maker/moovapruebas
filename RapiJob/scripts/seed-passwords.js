# ============================================================
# Regenera hashes bcrypt REALES (cost 12) para los usuarios seed.
# Requiere: npm install   (instala bcryptjs + pg)
# Uso:      npm run seed:passwords
# Los usuarios seed usan password = 'password123'.
# ============================================================
import bcrypt from 'bcryptjs';
import pg from 'pg';

const { DATABASE_URL } = process.env;
if (!DATABASE_URL) {
  console.error('Define DATABASE_URL en .env  (ej: postgres://postgres:postgres@localhost:5432/rapijob)');
  process.exit(1);
}
const hash = bcrypt.hashSync('password123', 12);
const pool = new pg.Pool({ connectionString: DATABASE_URL });
const r = await pool.query('UPDATE users SET password=$1::text RETURNING id,email', [hash]);
await pool.end();
console.log(`✅ ${r.rowCount} usuarios seed actualizados con hash bcrypt real: ${hash.slice(0,7)}... (password='password123')`);
