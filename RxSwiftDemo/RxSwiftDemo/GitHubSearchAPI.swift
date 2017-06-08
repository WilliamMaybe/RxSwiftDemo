//
//  GitHubSearchAPI.swift
//  RxSwiftDemo
//
//  Created by maybe on 2017/5/30.
//  Copyright © 2017年 Maybe Zh. All rights reserved.
//

import UIKit
import RxSwift

func exampleError(_ error: String, location: String = "\(#file):\(#line)") -> NSError {
    return NSError(domain: "ExampleError", code: -1, userInfo: [NSLocalizedDescriptionKey: "\(location): \(error)"])
}

struct Repository: CustomDebugStringConvertible {
    var name: String
    var url: String
}

extension Repository {
    var debugDescription: String {
        return "\(name) | \(url)"
    }
}

enum ServiceState {
    case offline, online
}

enum SearchRepositoryResponse {
    case repositories(repositories: [Repository], nextURL: URL?)
    case serviceOffline
    case limitExceeded
}

struct RepositoriesState {
    let repositories: [Repository]
    let serviceState: ServiceState?
    let limitExceeded: Bool
    
    static let empty = RepositoriesState(repositories: [], serviceState: nil, limitExceeded: false)
}

class GitHubSearchAPI {
    static let sharedAPI = GitHubSearchAPI()
    
    func search(_ query: String, loadNextPageTrigger: Observable<Void>) -> Observable<RepositoriesState> {
        print("Begin search \(query)")
        let escapedQuery = query.URLEscaped
        let url = URL(string: "https://api.github.com/search/repositories?q=\(escapedQuery)")!
        return recursivelySearch([], loadNextURL: url, loadNextPageTrigger: loadNextPageTrigger)
            .startWith(RepositoriesState.empty)
    }
    
    private func recursivelySearch(_ loadSoFar: [Repository], loadNextURL: URL, loadNextPageTrigger: Observable<Void>) -> Observable<RepositoriesState> {
        return loadSearchURL(loadNextURL).flatMap({ (response) -> Observable<RepositoriesState> in
            switch response {
                case .limitExceeded:
                    return Observable.just(RepositoriesState(repositories: loadSoFar, serviceState: .online, limitExceeded: true))
                case .serviceOffline:
                    return Observable.just(RepositoriesState(repositories: loadSoFar, serviceState: .offline, limitExceeded: false))
                case let .repositories(newRepositories, newNextURL):
                    var resultRepositories = loadSoFar
                    resultRepositories.append(contentsOf: newRepositories)
                    
                    let resultState = RepositoriesState(repositories: resultRepositories, serviceState: .online, limitExceeded: false)
                    
                    guard let nextURL = newNextURL else {
                        return Observable.just(resultState)
                    }
                
                    return Observable.concat([Observable.just(resultState),
                                              Observable.never().takeUntil(loadNextPageTrigger),
                                              self.recursivelySearch(resultRepositories, loadNextURL: nextURL, loadNextPageTrigger: loadNextPageTrigger)])
            }
        })
    }
    
    private func loadSearchURL(_ searchURL: URL) -> Observable<SearchRepositoryResponse> {
        return URLSession.shared
            .rx.response(request: URLRequest(url: searchURL))
            .retry(3)
            .map({ httpURLResponse, data -> SearchRepositoryResponse in
                if httpURLResponse.statusCode == 403 {
                    return .limitExceeded
                }
                    
                let jsonRoot = try GitHubSearchAPI.parseJSON(httpURLResponse, data: data)
                guard let json = jsonRoot as? [String : AnyObject] else {
                    throw exampleError("Casting to dictionary failed")
                }
                
                print("success")
                
                let repositories = try GitHubSearchAPI.parseRepositories(json)
                let nextURL = try GitHubSearchAPI.parseNextURL(httpURLResponse)
                return .repositories(repositories: repositories, nextURL: nextURL)
            })
    }
}

extension GitHubSearchAPI {
    private static let parseLinksPattern = "\\s*,?\\s*<([^\\>]*)>\\s*;\\s*rel=\"([^\"]*)\""
    private static let linksRegex = try! NSRegularExpression(pattern: parseLinksPattern, options: [.allowCommentsAndWhitespace])
    
    fileprivate static func parseLinks(_ links: String) throws -> [String: String] {
        
        let length = (links as NSString).length
        let matches = GitHubSearchAPI.linksRegex.matches(in: links, options: NSRegularExpression.MatchingOptions(), range: NSRange(location: 0, length: length))
        
        var result: [String: String] = [:]
        
        for m in matches {
            let matches = (1 ..< m.numberOfRanges).map { rangeIndex -> String in
                let range = m.rangeAt(rangeIndex)
                let startIndex = links.characters.index(links.startIndex, offsetBy: range.location)
                let endIndex = links.characters.index(links.startIndex, offsetBy: range.location + range.length)
                let stringRange = startIndex ..< endIndex
                return links.substring(with: stringRange)
            }
            
            if matches.count != 2 {
                throw exampleError("Error parsing links")
            }
            
            result[matches[1]] = matches[0]
        }
        
        return result
    }
    
    fileprivate static func parseNextURL(_ httpResponse: HTTPURLResponse) throws -> URL? {
        guard let serializedLinks = httpResponse.allHeaderFields["Link"] as? String else {
            return nil
        }
        
        let links = try GitHubSearchAPI.parseLinks(serializedLinks)
        
        guard let nextPageURL = links["next"] else {
            return nil
        }
        
        guard let nextUrl = URL(string: nextPageURL) else {
            throw exampleError("Error parsing next url `\(nextPageURL)`")
        }
        
        return nextUrl
    }
    
    fileprivate static func parseJSON(_ httpResponse: HTTPURLResponse, data: Data) throws -> AnyObject {
        if !(200 ..< 300 ~= httpResponse.statusCode) {
            throw exampleError("Call failed")
        }
        
        return try JSONSerialization.jsonObject(with: data, options: []) as AnyObject
    }
    
    fileprivate static func parseRepositories(_ json: [String: AnyObject]) throws -> [Repository] {
        guard let items = json["items"] as? [[String: AnyObject]] else {
            throw exampleError("Can't find items")
        }
        return try items.map { item in
            guard let name = item["name"] as? String,
                let url = item["url"] as? String else {
                    throw exampleError("Can't parse repository")
            }
            return Repository(name: name, url: url)
        }
    }
}

extension String {
    var URLEscaped: String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
    }
}
