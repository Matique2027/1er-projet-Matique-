const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Méthode non autorisée' });
  try {
    const token = (req.headers.authorization || '').replace('Bearer ', '');
    const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user) return res.status(401).json({ error: 'Non connecté' });
    const user = data.user;

    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
    const origin = req.headers.origin || `https://${req.headers.host}`;
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      customer_email: user.email,
      client_reference_id: user.id,
      subscription_data: { trial_period_days: 7, metadata: { user_id: user.id } },
      success_url: `${origin}/?paid=1`,
      cancel_url: `${origin}/`,
    });
    res.status(200).json({ url: session.url });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Impossible de créer le paiement' });
  }
};
