//
//  ProjectFlowUITests.swift
//  OPFCaptureBuilderUITests
//
//  UI tests for the basic project creation flow and the export screen. They run against
//  the real app in a simulator and use the accessibility identifiers declared in the views.
//

import XCTest

final class ProjectFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-OPFCaptureBuilderUITest"]
        app.launch()
    }

    /// Completes onboarding if the welcome screen is showing.
    private func passOnboardingIfNeeded() {
        let continueButton = app.buttons["welcome.continue"]
        if continueButton.waitForExistence(timeout: 5) {
            continueButton.tap()
        }
    }

    func testCreateProjectFlow() {
        passOnboardingIfNeeded()

        let newButton = app.buttons["projects.new"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10), "Projects screen should offer a New Project action")
        newButton.tap()

        let nameField = app.textFields["newproject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "The new project form should show a name field")
        nameField.tap()
        nameField.typeText("UI Test Project")

        let descriptionField = app.textViews["newproject.description"]
        if descriptionField.exists {
            descriptionField.tap()
            descriptionField.typeText("Created by a UI test")
        }

        let createButton = app.buttons["newproject.create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let row = app.buttons["project.row.UI Test Project"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The new project should appear in the list")
    }

    func testProjectDetailExposesExportAndValidation() {
        passOnboardingIfNeeded()

        app.buttons["projects.new"].tap()
        let nameField = app.textFields["newproject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Export Flow Project")
        app.buttons["newproject.create"].tap()

        let row = app.buttons["project.row.Export Flow Project"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.buttons["detail.validate"].waitForExistence(timeout: 5), "Validation entry point should exist")
        XCTAssertTrue(app.buttons["detail.export"].exists, "Export entry point should exist")

        app.buttons["detail.export"].tap()
        let shareButton = app.buttons["export.share"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5), "The export screen should offer a share action")
    }

    func testCreateSampleProjectAndValidate() {
        passOnboardingIfNeeded()

        app.buttons["projects.new"].tap()
        let sampleItem = app.buttons["Create Sample Project"]
        if sampleItem.waitForExistence(timeout: 5) {
            sampleItem.tap()
        } else {
            // The sample action lives in the Add menu; open it explicitly.
            app.navigationBars.buttons.element(boundBy: 1).tap()
            if sampleItem.waitForExistence(timeout: 5) { sampleItem.tap() }
        }

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'project.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The sample project should be created and listed")
        row.tap()

        app.buttons["detail.validate"].tap()
        XCTAssertTrue(app.buttons["validation.run"].waitForExistence(timeout: 5))
    }
}
