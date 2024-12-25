import SwiftUI

class MBTViewModel: ObservableObject {

    // in lieu of the normal OAUTH2 flow,
    // user receives an oauth2 access_token unique to their account during
    // login via special param ... still normal oauth2 with clientid and secret
    // but all done internally on the backend
    // since user has valid access/refresh token from moment of loginwill save some network back and forth, too ... user logs in or creates account with special mbtwidget url and then they receive an access_token
    let CLIENT_ID = "55723231"
    let CLIENT_SECRET = "2ZWK9sU2hMcQ3smbgaSqywNkcvGKbb53"
    
    // this will open other browser window
    // the callback will contain the token directly instead of the normal oauth2 flow
    // this is handled by .onOpenUrl
    func authenticateUser() {
        // Example: simulate a login flow that issues tokens directly
        let loginURL = "https://mybiketraffic.com/clients/login?client_id=\(CLIENT_ID)"
        guard let url = URL(string: loginURL) else { return }
        UIApplication.shared.open(url)
    }
    
    func syncDirectoryListing() {
        refreshAccessToken() { success in 
            guard let token = self.getAccessToken() else {
                print("Could not authenticate user")
                return
            }// try again after authen

            // Get the document directory path
            let fileManager = FileManager.default
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                do {
                    // Fetch directory contents
                    let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [])
                    let fileNames = fileURLs.map { $0.lastPathComponent } // Extract file names
                    
                    // Prepare JSON payload
                    let payload: [String: Any] = [
                        "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? "UnknownDevice",
                        "files": fileNames
                    ]
                    
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
                        print("Failed to serialize directory data")
                        return
                    }
                    
                    // OAuth2 token retrieval and API request
                    guard let url = URL(string: "https://mybiketraffic.com/clients/api_syncDirectory") else { return }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = jsonData
                    
                    // Perform the network request
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error = error {
                            print("Error syncing directory: \(error.localizedDescription)")
                            return
                        }
                        if let response = response as? HTTPURLResponse {
                            print("Response status code: \(response.statusCode)")
                        }
                    }
                    task.resume()
                    
                } catch {
                    print("Error reading directory: \(error.localizedDescription)")
                }
            } else {
                print("Failed to access the document directory.")
            }
        }
    }
    
    func isAccessTokenExpired() -> Bool {
        guard let expirationTimestamp = UserDefaults.standard.value(forKey: "OAuthAccessTokenExpiration") as? TimeInterval else {
            return true // No expiration saved; assume expired
        }
        return Date().timeIntervalSince1970 >= expirationTimestamp
    }

    
    func saveAccessToken(_ token: String, expiresIn: Int) {
        let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expirationTimestamp = expirationDate.timeIntervalSince1970
        
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OAuthAccessToken",
            kSecValueData as String: token.data(using: .utf8)!
        ]
        SecItemDelete(keychainQuery as CFDictionary) // Remove existing token
        SecItemAdd(keychainQuery as CFDictionary, nil)
        
        UserDefaults.standard.set(expirationTimestamp, forKey: "OAuthAccessTokenExpiration")
    }

    func saveRefreshToken(_ token: String) {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OAuthRefreshToken",
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        SecItemDelete(keychainQuery as CFDictionary) // Delete any existing token
        SecItemAdd(keychainQuery as CFDictionary, nil)
    }

    func getRefreshToken() -> String? {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OAuthRefreshToken",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject? = nil
        let status: OSStatus = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        }
        return nil
    }
    
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = getRefreshToken() else {
            print("No refresh token available")
            completion(false)
            return
        }

        let url = URL(string: "https://mybiketraffic.com/clients/refresh_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "YOUR_CLIENT_ID",
            "client_secret": "YOUR_CLIENT_SECRET"
        ]
        request.httpBody = bodyParameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Failed to refresh token: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            if let response = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let newAccessToken = response["access_token"] as? String,
               let newRefreshToken = response["refresh_token"] as? String,
               let expiresIn = response["expires_in"] as? Int {
                self.saveAccessToken(newAccessToken, expiresIn: expiresIn)
                self.saveRefreshToken(newRefreshToken)
                print("Tokens refreshed successfully")
                completion(true)
            } else {
                print("Failed to parse refresh token response")
                completion(false)
            }
        }
        task.resume()
    }
    
    func getAccessToken() -> String? {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OAuthAccessToken",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject? = nil
        let status: OSStatus = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        }
        return nil
    }
    
}
