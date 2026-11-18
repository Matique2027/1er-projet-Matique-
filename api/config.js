// Renvoie les infos publiques (sans danger) au navigateur
module.exports = (req, res) => {
  res.status(200).json({
    url: process.env.SUPABASE_URL,
    anon: process.env.SUPABASE_ANON_KEY,
  });
};
