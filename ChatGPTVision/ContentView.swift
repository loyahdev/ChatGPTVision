import SwiftUI
import AVFoundation
import Combine

class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVCapturePhotoCaptureDelegate {
    // Your existing properties
    var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?
    var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentPhotoData: Data?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var photoCaptured = false
    @Published var responseText: String = "Detecting Image"
    @Published var showLoading = false
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        setupCamera()
    }

    private func setResponseText(_ text: String) {
        DispatchQueue.main.async {
            self.responseText = text
        }
    }

    private func resetUI() {
        NotificationCenter.default.post(name: Notification.Name("ResetUI"), object: nil)
    }

    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
                try audioSession.setActive(true)
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let audioFilename = documentsPath.appendingPathComponent("recording.m4a")
                
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 8000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue
                ]
                
                self.audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
                self.audioRecorder?.delegate = self
                self.audioRecorder?.record()
            } catch {
                print("Failed to set up audio session or recorder: \(error.localizedDescription)")
            }
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder?.delegate = nil
        DispatchQueue.global(qos: .userInitiated).async {
            self.capturePhoto()
        }
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("Recording finished successfully.")
        } else {
            print("Recording failed.")
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .medium
        configureCamera(for: .back)
    }

    private func configureCamera(for position: AVCaptureDevice.Position) {
        // Remove current inputs and add new inputs based on the position
        captureSession?.beginConfiguration()
        
        if let inputs = captureSession?.inputs {
            for input in inputs {
                captureSession?.removeInput(input)
            }
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("Unable to access camera!")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
        } catch {
            print("Error setting device input: \(error.localizedDescription)")
        }

        if photoOutput != nil {
            captureSession?.removeOutput(photoOutput!)
        }

        photoOutput = AVCapturePhotoOutput()
        if captureSession?.canAddOutput(photoOutput!) == true {
            captureSession?.addOutput(photoOutput!)
        }

        captureSession?.commitConfiguration()
        currentCameraPosition = position
        if captureSession?.isRunning == false {
            captureSession?.startRunning()
        }
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        configureCamera(for: newPosition)
    }

    private func capturePhoto() {
        guard let photoOutput = self.photoOutput else {
            print("Photo output is not set up")
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = false
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }
        
        guard let photoData = photo.fileDataRepresentation() else {
            print("No photo data to represent")
            return
        }
        
        self.currentPhotoData = photoData
        self.photoCaptured = true
        DispatchQueue.global(qos: .userInitiated).async {
            self.uploadFiles()
        }
    }

    private func createMultipartBody(boundary: String, audioURL: URL, imageData: Data) -> Data {
        var body = Data()
        if let audioData = try? Data(contentsOf: audioURL) {
            let boundaryPrefix = "--\(boundary)\r\n"
            
            body.append("\(boundaryPrefix)Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
            
            body.append("\(boundaryPrefix)Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        }
        return body
    }

    private func playSpeech(from base64String: String) {
        guard let data = Data(base64Encoded: base64String) else {
            print("Failed to decode base64 speech data")
            return
        }
        
        do {
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.play()
        } catch {
            print("Failed to play audio: \(error.localizedDescription)")
        }
    }

    @MainActor private func updateLoadingState() {
        showLoading = false
        resetUI()
    }
    
    func uploadFiles() {
        guard let audioURL = audioRecorder?.url, let imageData = currentPhotoData else {
            print("Missing audio or image data")
            return
        }

        let url = URL(string: "https://chatgpt-vision-replica-production.up.railway.app/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(boundary: boundary, audioURL: audioURL, imageData: imageData)
        request.httpBody = httpBody
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error uploading files: \(error?.localizedDescription ?? "No data")")
                return
            }
            
            do {
                // Parse the JSON response
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let responseText = jsonResponse["response_text"] as? String,
                   let speechMP3 = jsonResponse["speech_mp3"] as? String {
                    
                    // Update the response text on the main thread
                    DispatchQueue.main.async {
                        self.setResponseText(responseText)
                        self.updateLoadingState()
                    }
                    
                    // Play the speech audio
                    self.playSpeech(from: speechMP3)
                }
            } catch {
                print("Failed to parse JSON response: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct ContentView: View {
    @State private var isSpeaking = false
    @State private var speakingText = "Start speaking"
    @State private var waitingText = "Taking a look now."
    @State private var timer: Timer?
    @State private var timer2: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    
    @ObservedObject private var audioManager = AudioManager()
    @State private var responseText = "Waiting."
    
    @State private var showingCredits = false
    let heights = stride(from: 0.1, through: 1.0, by: 0.1).map { PresentationDetent.fraction($0) }
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Image("visionaiicon")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(10)
                    //Spacer()
                    VStack {
                        Text("ChatGPT Vision Replica Demo")
                            .foregroundColor(.gray)
                            //.padding(.top, 16)
                            .multilineTextAlignment(.leading)
                            .padding(.trailing, 20)
                        Text("Vision History is not transferred between requests.")
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                            //.multilineTextAlignment(.center)
                            //.padding(.bottom, 12.5)
                    }
                }
                .padding(.top, 16)
                
                Spacer()
                
                ZStack {
                    CameraView(session: audioManager.captureSession)
                    //Rectangle()
                        .frame(width: 325, height: 435)
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                        .shadow(radius: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white, lineWidth: 4)
                        )
                    if audioManager.showLoading {
                        Text(waitingText)
                            .font(.system(size: 35))
                            .offset(y: -300)
                            .padding(.horizontal)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                    } else if isSpeaking {
                        Text(speakingText)
                            .font(.system(size: 35))
                            .offset(y: -300)
                            .padding(.horizontal)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    } else if responseText != "Waiting." {
                        Text(responseText)
                            .font(.system(size: 20))
                            .offset(y: -300)
                            .padding(.horizontal)
                            .padding(.bottom, 5)
                            .lineLimit(5)
                            .truncationMode(.tail)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
                .padding(.bottom, 35)
                
                HStack {
                    Button(action: {
                                showingCredits.toggle()
                    }) {
                        Image(systemName: "questionmark.circle")
                            //.frame(width: 20, height: 20)
                            .scaleEffect(CGSize(width: 1.75, height: 1.75))
                            //.foregroundColor(colorScheme == .dark ? .white : .gray)
                            .foregroundColor(.gray)
                            .padding(.top, 5)
                    }
                    .sheet(isPresented: $showingCredits) {
                        Text("This app was brought to you by loyahdev. This is a rendition of the real time vision capabilities of GPT-4o made by OpenAI.")
                            .presentationDetents([.height(100)])
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        guard !audioManager.showLoading else { return }

                        isSpeaking.toggle()
                        
                        if isSpeaking {
                            startSpeakingAnimation()
                            audioManager.startRecording()
                        } else {
                            stopSpeakingAnimation()
                            audioManager.stopRecording()
                            audioManager.showLoading = true
                            waitingText = "Taking a look now."
                            speak(waitingText)
                            startLookingAnimation()
                        }
                    }, label: {
                        if audioManager.showLoading {
                            ProgressView()
                                .scaleEffect(CGSize(width: 2.25, height: 2.25))
                        } else {
                            Image(systemName: "person.bubble")
                                .scaleEffect(CGSize(width: 2.5, height: 2.5))
                                .foregroundColor(colorScheme == .dark ? .white : .gray)
                                //.foregroundColor(.white)
                        }
                    })
                    .padding(.top, 15)
                    
                    Spacer()
                    
                    Button(action: {
                        audioManager.switchCamera()
                    }) {
                        Image(systemName: "camera.rotate")
                            .scaleEffect(CGSize(width: 1.75, height: 1.75))
                            //.foregroundColor(colorScheme == .dark ? .white : .gray)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.bottom, 25)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetUI"))) { _ in
            isSpeaking = false
            audioManager.showLoading = false
        }
        .onChange(of: audioManager.responseText) { newText in
            responseText = newText
        }
    }
    
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
    
    func startSpeakingAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            speakingText = speakingText == "Start speaking..." ? "Start speaking" : "\(speakingText)."
        }
    }
    
    func startLookingAnimation() {
        timer2?.invalidate()
        timer2 = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            waitingText = waitingText == "Taking a look now..." ? "Taking a look now" : "\(waitingText)."
        }
    }
    
    func stopSpeakingAnimation() {
        timer?.invalidate()
        timer = nil
    }
    
    func stopVideoAnimation() {
        timer2?.invalidate()
        timer2 = nil
    }
}

struct CameraView: UIViewControllerRepresentable {
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: CameraView
        init(parent: CameraView) {
            self.parent = parent
        }
    }
    
    var session: AVCaptureSession?
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = CameraViewController()
        viewController.session = session
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let cameraViewController = uiViewController as? CameraViewController {
            cameraViewController.session = session
        }
    }
}

class CameraViewController: UIViewController {
    var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewLayer()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewLayerFrame()
    }
    
    private func setupPreviewLayer() {
        if let session = session {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer!)
            updatePreviewLayerFrame()
        }
    }
    
    private func updatePreviewLayerFrame() {
        previewLayer?.frame = view.bounds
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
