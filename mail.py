"""
Micro-service Flask pour l'envoi automatisé de formulaires de contact via SMTP.
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os

app = Flask(__name__)
# Permet à ton site (frontend) de parler au serveur (backend)
CORS(app)

# CONFIGURATION (Idéalement, mets ça dans des variables d'environnement)
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SENDER_EMAIL = "" # Ton adresse Gmail
SENDER_PASSWORD = "" # Ton mot de passe d'application (PAS le vrai)
RECEIVER_EMAIL = "" # L'adresse qui reçoit les messages du site

@app.route('/send-contact', methods=['POST'])
def send_contact():
    data = request.json

    nom = data.get('nom')
    prenom = data.get('prenom')
    email_visiteur = data.get('email')
    message_content = data.get('message')

    if not all([nom, email_visiteur, message_content]):
        return jsonify({"error": "Champs manquants"}), 400

    # Création du message
    subject = f"Nouveau contact A.J.C de : {nom} {prenom}"
    body = f"""
    Nouveau message reçu depuis le site A.J.C.

    Nom : {nom} {prenom}
    Email : {email_visiteur}

    Message :
    {message_content}
    """

    msg = MIMEMultipart()
    msg['From'] = SENDER_EMAIL
    msg['To'] = RECEIVER_EMAIL
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain'))

    try:
        # Connexion au serveur SMTP de Google
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls() # Sécuriser la connexion
        server.login(SENDER_EMAIL, SENDER_PASSWORD)
        server.sendmail(SENDER_EMAIL, RECEIVER_EMAIL, msg.as_string())
        server.quit()

        return jsonify({"success": True, "message": "Email envoyé avec succès"})
    except Exception as e:
        print(f"Erreur d'envoi: {e}")
        return jsonify({"success": False, "message": "Erreur serveur"}), 500

if __name__ == '__main__':
    # Lance le serveur sur le port 5000
    app.run(debug=True, port=5000)

