# RxSwiftDemo
## GitHubSearch
使用接口搜索GiHub仓库并显示
### Repository
创建实体，`Repository`是仓库实体，`SearchRepositoryResponse`是网络请求的结果，`RepositoriesState`是数据解析后对外提供的最终产物

```
struct Repository: CustomDebugStringConvertible {
    var name: String
    var url: String
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
```
### GitHubSearchAPI
该类拥有一个公开方法和若干个私有方法

在经过网络请求后进行数据上的转变，`response`正是`SearchRepositoryReponse`，这里需要将其转成`RepositoriesState`供外部使用

在最后返回concat时有一条`Observable.never().takeUntil(loadNextPageTrigger)`，concat的特性就是依次Observable在complete之后才会进行下一个Observable订阅，因此在这里只有触发了加载下一页的命令，才会进行继续获取下一页的网络请求

```
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
```

```
	URLSession.shared
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
  
                let repositories = try GitHubSearchAPI.parseRepositories(json)
                let nextURL = try GitHubSearchAPI.parseNextURL(httpURLResponse)
                return .repositories(repositories: repositories, nextURL: nextURL)
            })
```

### GitHubSearchViewController
使用RxDataSource绑定tableView的dataSource。在这里如果直接使用UITableViewController则会一直报错已经设置过delegate，不知道是不是使用问题。

`sectionModel`是库提供的结构体，相当于每个section的id和item

```
let dataSource = RxTableViewSectionedReloadDataSource<SectionModel<String, Repository>>()
```
cell的配置，麻烦的是没有自动补全，需要自己将closure打出来ORZ

```
dataSource.configureCell = { (_, tv, ip, repository) in
            let cell = tv.dequeueReusableCell(withIdentifier: "Cell")!
            cell.textLabel?.text = repository.name
            cell.detailTextLabel?.text = repository.url
            return cell
        }
```
接下来是将searchbar的输入情况转换成

```
let searchResult = self.searchBar.rx.text.orEmpty.asDriver()
            .throttle(0.3)
            .distinctUntilChanged()
            .flatMap { (query) -> Driver<RepositoriesState> in
                if query.isEmpty {
                    return Driver.just(RepositoriesState.empty)
                }
                return GitHubSearchAPI.sharedAPI.search(query, loadNextPageTrigger: loadNextPageTrigger)
                    .asDriver(onErrorJustReturn: RepositoriesState.empty)
        }
        
        searchResult
            .map { [SectionModel(model: "Repositories", items: $0.repositories)] }
            .drive(tableView.rx.items(dataSource: dataSource))
            .addDisposableTo(disposeBag)
```