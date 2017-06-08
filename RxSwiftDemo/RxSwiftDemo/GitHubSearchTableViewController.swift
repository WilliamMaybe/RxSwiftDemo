//
//  GitHubSearchTableViewController.swift
//  RxSwiftDemo
//
//  Created by maybe on 2017/5/30.
//  Copyright © 2017年 Maybe Zh. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

extension UIScrollView {
    func  isNearBottomEdge(edgeOffset: CGFloat = 20.0) -> Bool {
        return self.contentOffset.y + self.frame.size.height + edgeOffset > self.contentSize.height
    }
}

class GitHubSearchTableViewController: UIViewController, UITableViewDelegate {

    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet var tableView: UITableView!
    
    private lazy var disposeBag = DisposeBag()
    
    let dataSource = RxTableViewSectionedReloadDataSource<SectionModel<String, Repository>>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        dataSource.configureCell = { (_, tv, ip, repository) in
            let cell = tv.dequeueReusableCell(withIdentifier: "Cell")!
            cell.textLabel?.text = repository.name
            cell.detailTextLabel?.text = repository.url
            return cell
        }
        
        dataSource.titleForHeaderInSection = { dataSource, sectionIndex in
            let section = dataSource[sectionIndex]
            return section.items.count > 0 ? "Repositories (\(section.items.count))" : "No repositories found"
        }
        
        let loadNextPageTrigger = tableView.rx.contentOffset
            .flatMap { [unowned self] _ in
                self.tableView.isNearBottomEdge() ? Observable.just() : Observable.empty()
        }
        
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
        
        tableView.rx.contentOffset
            .subscribe { _ in
                if self.searchBar.isFirstResponder {
                    _ = self.searchBar.resignFirstResponder()
                }
            }
            .addDisposableTo(disposeBag)
        
        tableView.rx.setDelegate(self).addDisposableTo(disposeBag)
    }
}
