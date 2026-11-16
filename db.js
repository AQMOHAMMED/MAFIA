// مخزن البيانات: الحسابات، الصداقات، والألعاب.
// كل البيانات بتنحفظ بالذاكرة وبتنكتب (مع تأخير بسيط) على:
//   - قاعدة PostgreSQL إذا في متغير DATABASE_URL (عشان ما تضيع مع إعادة التشغيل على Render)
//   - أو ملف JSON محلي (data/db.json) غير هيك
const fs = require('fs');
const path = require('path');

const EMPTY = () => ({ users: {}, sessions: {}, requests: [], games: [], gameSeq: 0 });

const db = {
  data: EMPTY(),
  kind: process.env.DATABASE_URL ? 'postgres' : 'file',
  _timer: null,
  _saving: Promise.resolve(),
  _pool: null,
  file: path.join(process.env.DATA_DIR || path.join(__dirname, 'data'), 'db.json'),

  async load() {
    try {
      if (this.kind === 'postgres') {
        const { Pool } = require('pg');
        const url = process.env.DATABASE_URL.trim();
        const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url);
        // بنشيل sslmode من الرابط ونحدد التشفير هون، عشان مكتبة pg ما تطبع تحذيرات
        const u = new URL(url);
        u.searchParams.delete('sslmode');
        this._pool = new Pool({
          connectionString: u.toString(),
          ssl: local ? false : { rejectUnauthorized: false },
          max: 3,
        });
        await this._pool.query('CREATE TABLE IF NOT EXISTS mafia_store (id INT PRIMARY KEY, data JSONB NOT NULL)');
        const r = await this._pool.query('SELECT data FROM mafia_store WHERE id = 1');
        if (r.rows[0]) this.data = { ...EMPTY(), ...r.rows[0].data };
      } else if (fs.existsSync(this.file)) {
        this.data = { ...EMPTY(), ...JSON.parse(fs.readFileSync(this.file, 'utf8')) };
      }
      console.log(`DB (${this.kind}): ${Object.keys(this.data.users).length} users, ${this.data.games.length} games`);
    } catch (e) {
      console.error('ما قدرنا نحمّل البيانات', e);
      if (this.kind === 'postgres') throw e; // ما بنبلش بقاعدة فاضية فوق بيانات حقيقية
    }
  },

  // حفظ مؤجّل: بنجمع التغييرات ونكتبها مرة وحدة
  save() {
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.flush(), 400);
  },

  flush() {
    clearTimeout(this._timer);
    const json = JSON.stringify(this.data);
    this._saving = this._saving.then(async () => {
      try {
        if (this.kind === 'postgres') {
          await this._pool.query(
            'INSERT INTO mafia_store (id, data) VALUES (1, $1) ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data', [json]);
        } else {
          fs.mkdirSync(path.dirname(this.file), { recursive: true });
          const tmp = this.file + '.tmp';
          fs.writeFileSync(tmp, json);
          fs.renameSync(tmp, this.file);
        }
      } catch (e) { console.error('ما قدرنا نحفظ البيانات', e); }
    });
    return this._saving;
  },
};

module.exports = db;
