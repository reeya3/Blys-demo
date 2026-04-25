const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({ 
    message: 'Hello from Blys DevOps Challenge!', 
    timestamp: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`Blys app listening on port ${port}`);
});

app.get('/health', (req, res) => res.status(200).json({ status: 'ok' }));
