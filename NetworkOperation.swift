//
//  NetworkOperation.swift
//  Radiant Tap Essentials
//
//  Copyright © 2017 Radiant Tap
//  MIT License · http://choosealicense.com/licenses/mit/
//

import Foundation

/// Subclass of [AsyncOperation](https://github.com/radianttap/Swift-Essentials/blob/master/Operation/AsyncOperation.swift)
///	that handles all aspects of direct data download over network.
///	It uses QoS.utility by default.
///
///	It will automatically handle Auth challenges, using URLSession.serverTrustPolicy. Returns `userCancelledAuthentication` error if that fails.
///
///	In the simplest case, you can supply just URLRequest and a `Callback` which accepts `NetworkPayload` instance.
///
///	Or you can also supply custom URLSessionConfiguration just for this request.
final class NetworkOperation: AsyncOperation {
	typealias Callback = (NetworkPayload) -> Void

	/// Set network start timestamp, creates URLSessionDataTask and starts it (resume)
	override func workItem() {
		payload.start()

		task = localURLSession.dataTask(with: payload.urlRequest)
		task?.resume()
	}

	fileprivate func finish() {
		payload.end()
		markFinished()

		callback(payload)
	}

	internal override func cancel() {
		super.cancel()

		task?.cancel()
		payload.error = .cancelled

		finish()
	}

	required init() {
		fatalError("Use the `init(urlRequest:urlSessionConfiguration:callback:)`")
	}


	/// Designated initializer
	///
	/// - Parameters:
	///   - request: `URLRequest` value to execute
	///   - urlSessionConfiguration: `URLSessionConfiguration` for this particular network call. Fallbacks to `default` if not specified
	///   - callback: A closure to pass the result back
	init(urlRequest: URLRequest,
	     urlSessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.default,
	     callback: @escaping (NetworkPayload) -> Void)
	{
		self.payload = NetworkPayload(urlRequest: urlRequest)
		self.callback = callback
		self.urlSessionConfiguration = urlSessionConfiguration
		super.init()

		self.qualityOfService = .utility
	}

	fileprivate(set) var payload: NetworkPayload
	private(set) var callback: Callback

	fileprivate var incomingData = Data()

	///	Configuration to use for the URLSession that will handle `urlRequest`
	private(set) var urlSessionConfiguration : URLSessionConfiguration

	///	URLSession is built for each request. Delegate calls are handled internally
	fileprivate var localURLSession: URLSession {
		return URLSession(configuration: urlSessionConfiguration,
		                  delegate: self,
		                  delegateQueue: nil)
	}

	///	Actual network task, generated by `localURLSession`
	fileprivate var task: URLSessionDataTask?

	var allowEmptyData: Bool = true
}


extension NetworkOperation: URLSessionDataDelegate {

	func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		if isCancelled {
			return
		}

		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			let trust = challenge.protectionSpace.serverTrust!
			let host = challenge.protectionSpace.host
			guard session.serverTrustPolicy.evaluate(trust, forHost: host) else {
				completionHandler(URLSession.AuthChallengeDisposition.rejectProtectionSpace, nil)

				payload.error = .urlError( NSError(domain: NSURLErrorDomain, code: URLError.userCancelledAuthentication.rawValue, userInfo: nil) as? URLError )
				finish()
				return
			}

			let credential = URLCredential(trust: trust)
			completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential)
		}

		completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
	}

	//	this checks the response headers
	final func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		if isCancelled {
			return
		}

		//	Check the response code and react appropriately
		guard let httpResponse = response as? HTTPURLResponse else {
			payload.error = .invalidResponse
			completionHandler(.cancel)
			finish()
			return
		}

		payload.response = httpResponse

		//	always allow data to arrive in order to extract possible API error messages to show up
		completionHandler(.allow)
	}

	//	this will be called multiple times while the data is coming in
	final func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		if isCancelled {
			return
		}

		incomingData.append(data)
	}

	final func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
		if isCancelled {
			return
		}

		if let e = error {
			payload.error = .urlError(e as? URLError)
		} else {
			if incomingData.isEmpty {
				payload.error = .noData
			} else {
				payload.data = incomingData
			}
		}

		finish()
	}
}

