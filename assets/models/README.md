# Vosk Model

Please download a Vosk model (e.g., `vosk-model-small-en-us-0.15`) from [https://alphacephei.com/vosk/models](https://alphacephei.com/vosk/models).
Unzip the downloaded file and place the folder here.
Rename the folder to `model` for easier access, or update the code in `lib/services/live_audio_service.dart` to match your model folder name.

Example structure:
assets/
  models/
    model/
      am/
      conf/
      ...
