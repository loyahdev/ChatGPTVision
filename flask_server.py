from flask import Flask, request, jsonify
import openai
import os
import time
import base64
from io import BytesIO

app = Flask(__name__)

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')
        
@app.route('/')
def index():
    return jsonify({"Server Running": "Welcome to your favourite server!"})

@app.route('/process', methods=['POST'])
def process_files():
    print("Request received")

    # Check if files are in the request
    if 'audio' not in request.files or 'image' not in request.files:
        return jsonify({'error': 'Audio or image file is missing'}), 400

    audio_file = request.files['audio']
    image_file = request.files['image']

    # Save the audio file
    audio_path = os.path.join(os.getcwd(), "audio_file.m4a")
    audio_file.save(audio_path)

    # Transcribe audio using OpenAI Whisper API
    with open(audio_path, "rb") as audio:
        transcript_response = openai.audio.transcriptions.create(
            model="whisper-1",
            file=audio
        )

    transcript = transcript_response.text
    print(f"Transcript: {transcript}")

    image_path = os.path.join(os.getcwd(), "image_file.png")
    image_file.save(image_path)

    # Verify image format and size
    image_size = os.path.getsize(image_path)
    if image_size > 10 * 1024 * 1024:
        return jsonify({'error': 'Image file size exceeds 10 MB'}), 400
    
    # Encode image to base64
    base64_image = encode_image(image_path)

    response = openai.chat.completions.create(
        model="gpt-4o",
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Here's the question: " + transcript + ". Make the response quick and concise. ONLY and ONLY tell what the main thing the image is or what I asked for. Make it human like and make it maximum 2-3 sentences of a response unless more is needed."},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": "data:image/jpeg;base64," + base64_image,
                        },
                    },
                ],
            }
        ],
        max_tokens=50,
    )

    response_text = response.choices[0].message.content
    print(f"Response: {response_text}")

    # Generate speech from the response text using OpenAI's TTS API
    speech_file = BytesIO()
    tts_response = openai.audio.speech.create(
        model="tts-1",
        voice="alloy",
        input=response_text
    )

    tts_response.stream_to_file(speech_file)
    speech_file.seek(0)  # Rewind the buffer for reading

    # Encode the MP3 file to base64
    speech_base64 = base64.b64encode(speech_file.read()).decode('utf-8')

    # Return both the response text and the speech MP3 file
    return jsonify({
        'response_text': response_text,
        'speech_mp3': speech_base64
    })

if __name__ == '__main__':
    app.run(debug=True, port=os.getenv("PORT", default=5000))