const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');

async function rawBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(typeof c === 'string' ? Buffer.from(c) : c);
  return Buffer.concat(chunks);
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).end();
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  let event;
  try {
    event = stripe.webhooks.constructEvent(
      await rawBody(req),
      req.headers['stripe-signature'],
      process.env.STRIPE_WEBHOOK_SECRET
    );
  } catch (e) {
    return res.status(400).send('Signature invalide');
  }

  const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const ts = (n) => (n ? new Date(n * 1000).toISOString() : null);

  async function save(sub, userId) {
    userId = userId || sub.metadata?.user_id;
    if (!userId) return;
    const end = sub.current_period_end ?? sub.items?.data?.[0]?.current_period_end;
    const { error } = await admin.from('subscriptions').upsert({
      user_id: userId,
      stripe_customer_id: sub.customer,
      stripe_subscription_id: sub.id,
      status: sub.status,
      trial_end: ts(sub.trial_end),
      current_period_end: ts(end),
    });
    if (error) throw error;
  }

  try {
    if (event.type === 'checkout.session.completed') {
      const s = event.data.object;
      if (s.subscription) {
        const sub = await stripe.subscriptions.retrieve(s.subscription);
        await save(sub, s.client_reference_id);
      }
    } else if (event.type.startsWith('customer.subscription.')) {
      await save(event.data.object);
    }
    res.status(200).json({ received: true });
  } catch (e) {
    console.error(e);
    res.status(500).send('Erreur serveur');
  }
};
