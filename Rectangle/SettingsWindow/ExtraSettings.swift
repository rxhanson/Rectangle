/// ExtraSettings.swift

import AppKit

private var integerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.allowsFloats = false
    formatter.minimum = 1
    return formatter
}()

// MARK: - TileSettingsView

final class TileSettingsView: NSView, NSTextFieldDelegate {

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: String(localized:"Tile Windows in Rows/Columns"))
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }()

    private let columnsLabel = NSTextField(labelWithString: String(localized: "Maximum windows per column"))
    private let columnsTextField = NSTextField()
    private let columnsStepper = NSStepper()

    private let rowsLabel = NSTextField(labelWithString: String(localized: "Maximum windows per row"))
    private let rowsTextField = NSTextField()
    private let rowsStepper = NSStepper()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // --- Setup Column Controls ---
        columnsTextField.formatter = integerFormatter
        columnsTextField.alignment = .right
        columnsTextField.delegate = self
        columnsTextField.integerValue = Defaults.tileColumnsMaxWindows.value
        columnsTextField.translatesAutoresizingMaskIntoConstraints = false
        columnsTextField.widthAnchor.constraint(equalToConstant: 50).isActive = true

        configureStepper(columnsStepper, value: Defaults.tileColumnsMaxWindows.value)
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsStepperChanged(_:))

        let columnsRow = NSStackView(views: [columnsLabel, NSView(), columnsTextField, columnsStepper])
        columnsRow.orientation = .horizontal
        columnsRow.alignment = .centerY
        columnsRow.spacing = 8

        // --- Setup Row Controls ---
        rowsTextField.formatter = integerFormatter
        rowsTextField.alignment = .right
        rowsTextField.delegate = self
        rowsTextField.integerValue = Defaults.tileRowsMaxWindows.value
        rowsTextField.translatesAutoresizingMaskIntoConstraints = false
        rowsTextField.widthAnchor.constraint(equalToConstant: 50).isActive = true

        configureStepper(rowsStepper, value: Defaults.tileRowsMaxWindows.value)
        rowsStepper.target = self
        rowsStepper.action = #selector(rowsStepperChanged(_:))

        let rowsRow = NSStackView(views: [rowsLabel, NSView(), rowsTextField, rowsStepper])
        rowsRow.orientation = .horizontal
        rowsRow.alignment = .centerY
        rowsRow.spacing = 8

        // --- Main Vertical Stack Layout ---
        let mainStack = NSStackView(views: [titleLabel, rowsRow, columnsRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            columnsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            rowsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    private func configureStepper(_ stepper: NSStepper, value: Int) {
        stepper.minValue = 1
        stepper.maxValue = Double(Int.max)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.integerValue = value
    }

    // MARK: - Actions

    @objc private func columnsStepperChanged(_ sender: NSStepper) {
        let newValue = sender.integerValue
        columnsTextField.integerValue = newValue
        Defaults.tileColumnsMaxWindows.value = newValue
    }

    @objc private func rowsStepperChanged(_ sender: NSStepper) {
        let newValue = sender.integerValue
        rowsTextField.integerValue = newValue
        Defaults.tileRowsMaxWindows.value = newValue
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let val = max(1, textField.integerValue)

        if textField === columnsTextField {
            columnsStepper.integerValue = val
            Defaults.tileColumnsMaxWindows.value = val
        } else if textField === rowsTextField {
            rowsStepper.integerValue = val
            Defaults.tileRowsMaxWindows.value = val
        }
    }
}

// MARK: - WidthSettingsView

final class WidthSettingsView: NSView, NSTextFieldDelegate {

    private let widthStepLabel = NSTextField(labelWithString: String(localized: "Width Step (px)"))
    private let widthStepTextField = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        widthStepTextField.formatter = integerFormatter
        widthStepTextField.alignment = .right
        widthStepTextField.delegate = self
        widthStepTextField.integerValue = Int(Defaults.widthStepSize.value)
        widthStepTextField.translatesAutoresizingMaskIntoConstraints = false
        widthStepTextField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let rowStack = NSStackView(views: [widthStepLabel, NSView(), widthStepTextField])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY

        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let val = max(1, widthStepTextField.integerValue)
        Defaults.widthStepSize.value = Float(val)
    }
}
