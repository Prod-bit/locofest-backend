const express = require('express');
const Stripe = require('stripe');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json()); // Pour parser le body JSON

// Utilisation de la variable d'environnement pour la clé Stripe
const stripe = Stripe(process.env.STRIPE_SECRET_KEY);

app.post('/create-checkout-session', async (req, res) => {
  const { uid } = req.body;
  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [
        {
          price: "price_1RqDLRC1pv51tIEWYcI7ROms", // Ton ID de prix Stripe
          quantity: 1,
        },
      ],
      success_url: 'https://locofest.net/success.html',
      cancel_url: 'https://locofest.net/cancel.html',
      metadata: { uid },
    });
    res.send(session.url);
  } catch (err) {
    res.status(500).send({ error: err.message });
  }
});

// Nouvelle route pour annuler l'abonnement Stripe
app.post('/cancel-subscription', async (req, res) => {
  const { uid } = req.body;
  try {
    // Recherche tous les abonnements actifs (limit augmenté)
    const subscriptions = await stripe.subscriptions.list({
      status: 'active',
      limit: 100,
    });

    // Trouve l'abonnement dont le metadata.uid correspond
    const subscription = subscriptions.data.find(sub => sub.metadata && sub.metadata.uid === uid);

    if (!subscription) {
      return res.status(404).send({ error: "Abonnement non trouvé pour cet utilisateur." });
    }

    // Annule l'abonnement Stripe
    await stripe.subscriptions.cancel(subscription.id);

    res.send({ success: true });
  } catch (err) {
    res.status(500).send({ error: err.message });
  }
});

app.listen(4242, () => console.log('Server running on port 4242'));