# ChatGPTVision

This was a project I made to show how you can recreate the vision capabilities of ChatGPT's demos using there own API's and simple image processing.

![IMG_E619A4CBF386-1-2](https://github.com/user-attachments/assets/97271651-bda8-466a-8d15-e875061120e9)

### Most features have not been completed but are planned if I come around to finishing the app.

## Installation Instructions
1. Go to the releases tab and download the latest app zip file.
2. Extract the zip and open the .xcodeproj file
3. In the Signing and Capabilities section in the main project change the signing team to your own developer account.

4. Either run the flask_server.py file to host the API requests with OpenAI or host the python file on a service such as Railway or Replit.
5. Change the URL string on line 200 of the ContentView.swift file to the server link of the python flask server. In my case:
```swift
200: let url = URL(string: "https://chatgpt-vision-replica-production.up.railway.app/process")!
```
6. Run the app in a simulator or your iOS device and test.

### I might eventually change the python flask server to be locally Swift but that will happen later on.
