QT += core gui multimedia testlib dbus concurrent
CONFIG += c++17 console testcase
TARGET = backend_tests
TEMPLATE = app
INCLUDEPATH += ../src
SOURCES += backend_tests.cpp
include(../src/common.pri)
