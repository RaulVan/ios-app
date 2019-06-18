import UIKit

class TransactionsViewController<CellType: SnapshotCell>: UITableViewController {
    
    var dataSource: SnapshotDataSource!
    
    private let loadNextPageThreshold = 20
    private let headerReuseId = "header"
    private let cellReuseId = "cell"
    
    private lazy var filterController = AssetFilterViewController.instance()
    
    convenience init(category: SnapshotDataSource.Category) {
        self.init()
        self.dataSource = SnapshotDataSource(category: category)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 60
        tableView.separatorStyle = .none
        tableView.register(CellType.self, forCellReuseIdentifier: cellReuseId)
        tableView.register(AssetHeaderView.self, forHeaderFooterViewReuseIdentifier: headerReuseId)
        dataSource.onReload = { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.tableView.reloadData()
            weakSelf.tableView.checkEmpty(dataCount: weakSelf.dataSource.snapshots.count,
                                          text: Localized.WALLET_NO_TRANSACTION,
                                          photo: R.image.wallet.ic_no_transaction()!)
        }
        dataSource.reloadFromLocal()
        dataSource.reloadFromRemote()
        updateTableViewContentInset()
    }
    
    @available(iOS 11.0, *)
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableViewContentInset()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return dataSource.titles.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.snapshots[section].count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath) as! CellType
        let snapshot = dataSource.snapshots[indexPath.section][indexPath.row]
        cell.render(snapshot: snapshot)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: headerReuseId) as! AssetHeaderView
        view.label.text = dataSource.titles[section]
        return view
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let distance = dataSource.distanceToLastItem(of: indexPath), distance <= loadNextPageThreshold else {
            return
        }
        dataSource.loadMoreIfPossible()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let snapshot = dataSource.snapshots[indexPath.section][indexPath.row]
        DispatchQueue.global().async { [weak self] in
            guard let asset = AssetDAO.shared.getAsset(assetId: snapshot.assetId) else {
                return
            }
            DispatchQueue.main.async {
                self?.navigationController?.pushViewController(SnapshotViewController.instance(asset: asset, snapshot: snapshot), animated: true)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let title = dataSource.titles[section]
        return title.isEmpty ? .leastNormalMagnitude : 44
    }
    
    private func updateTableViewContentInset() {
        if view.compatibleSafeAreaInsets.bottom < 1 {
            tableView.contentInset.bottom = 10
        } else {
            tableView.contentInset.bottom = 0
        }
    }
    
}

extension TransactionsViewController: ContainerViewControllerDelegate {
    
    var prefersNavigationBarSeparatorLineHidden: Bool {
        return true
    }
    
    func barRightButtonTappedAction() {
        filterController.delegate = self
        present(filterController, animated: true, completion: nil)
    }
    
    func imageBarRightButton() -> UIImage? {
        return UIImage(named: "Wallet/ic_filter_large")
    }
    
}

extension TransactionsViewController: AssetFilterViewControllerDelegate {
    
    func assetFilterViewController(_ controller: AssetFilterViewController, didApplySort sort: Snapshot.Sort, filter: Snapshot.Filter) {
        tableView.setContentOffset(.zero, animated: false)
        dataSource.setSort(sort, filter: filter)
    }
    
}
