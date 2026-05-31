/// WindowMover.swift

import Foundation

protocol WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters)
}
