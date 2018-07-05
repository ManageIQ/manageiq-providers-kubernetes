# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Unreleased as of Sprint 89 ending 2018-07-02

### Fixed
- Kubevirt should reports its auth status [(#260)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/260)

## Unreleased as of Sprint 88 ending 2018-06-18

### Fixed
- Kubevirt should report its own status [(#259)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/259)

## Gaprindashvili-3 - Released 2018-05-15

### Added
- Keep quota history by archiving [(#198)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/198)

### Fixed
- Avoid refresh crash on Service without matchin Endpoints [(#242)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/242)
- Propagate userid through to create a scanning job with current userid [(#244)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/244)
- change evaluation target in openscap reports to image name [(#248)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/248)

## Unreleased as of Sprint 83 ending 2018-04-09

### Fixed
- Change saver_strategy value to String [(#246)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/246)

## Gaprindashvili-2 released 2018-03-06

### Fixed
- Change alert definition meta [(#217)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/217)

## Unreleased as of Sprint 80 ending 2018-02-26

### Fixed
- abort container ssa if can't fetch metadata [(#233)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/233)

## Unreleased as of Sprint 79 ending 2018-02-12

### Added
- Properly support "security_protocol" for alerts endpoint [(#230)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/230)
- Add a 'Container Project Discovered' event [(#226)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/226)
- We need to use existing relation to project so we build valid query [(#202)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/202)

## Gaprindashvili-1 - Released 2018-01-31

### Added
- Tag mapping in graph refresh [(#162)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/162)
- Parse requests and limits for Persistent Volume Claim [(#116)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/116)
- Adding cve_url and image_tag to global image_inspector settings [(#120)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/120)
- Prometheus alerts [(#40)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/40)
- Image scanning: Add image name to task name [(#105)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/105)
- Add prometheus capture context [(#71)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/71)
- Option needed for new ems_refresh.openshift.store_unused_images setting [(#11)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/11)
- Remove use_ar_object to speedup the saving [(#88)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/88)
- Update Hawkular version [(#56)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/56)
- Using the new options for image-scanning options [(#45)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/45)
- Collect container definition limits [(#22)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/22)
- Add a setting to only send DELETED notices [(#154)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/154)
- Parse and save quota scopes[(#190)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/190)
- Support multiple imagePullSecret secrets for inspector-admin SA [(#199)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/199)
- Cast quota values to float in parser, to match float columns [(#205)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/205)

### Fixed
- Make sure Container has always the right STI type [(#177)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/177)
- Improve Hawkular metrics collection [(#159)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/159)
- Fix Inventory Collector has_required_role? [(#163)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/163)
- Ignore ManagerRefresh::Target unless Graph Refresh is configured [(#151)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/151)
- Use Proetheus timeouts from settings [(#167)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/167)
- Prefix ems_ref with object type in event hash [(#123)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/123)
- Dont return an empty set when something goes wrong [(#122)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/122)
- Fail on creating scanning job with image instance [(#119)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/119)
- Fix net_usage_rate_average units [(#118)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/118)
- Enable graph refresh (batch strategy) by default [(#112)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/112)
- Scanning::Job always cleanup all signals in cleanup [(#99)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/99)
- Convert quotas to numeric values [(#69)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/69)
- Add mising metrics authentication [(#109)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/109)
- Container Template: convert params to hashes [(#97)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/97)
- Skip invalid container_images [(#94)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/94)
- Add ContainerImage raise event post processing job [(#77)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/77)
- Remove seemingly unnecessary ignoring of SIGTERM [(#96)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/96)
- Fix fallouts from ContainerTemplate STI [(#81)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/81)
- Don't start CollectorWorker if Graph Refresh disabled [(#153)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/153)
- Disable inventory collector worker by default [(#160)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/160)
- Make sure targeted refresh does not duplicate entities [(#145)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/145)
- Prometheus Alert flow changes [(#149)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/149)
- Make capture interval a multiple of 30s [(#187)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/187)
- Fix alerts SSL validation trusting custom store [(#192)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/192)
- Make container events belong to pod [(#181)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/181)
- Improve Prometheus metrics collection [(#132)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/132)
- Use prometheus client instead of faraday [(#195)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/195)
- ensure monitoring manager is created or deleted on provider update [(#188)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/188)

## Unreleased as of Sprint 78 ending 2018-01-29

### Added
- Migrate model display names from locale/en.yml to plugin [(#218)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/218)
- Support KubeVirt provider [(#197)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/197)

### Fixed
- only use the ImageAcquireError field [(#222)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/222)
- Skip hostname validation for monitoring manager [(#220)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/220)

## Unreleased as of Sprint 77 ending 2018-01-15

### Fixed
- Add a queue metrics capture method to container manager [(#206)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/206)

## Unreleased as of Sprint 75 ending 2017-12-11

### Added
- read image acquiring status [(#174)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/174)

## Unreleased as of Sprint 74 ending 2017-11-27

### Added
- Enable getting multiple alert for an incident [(#171)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/171)

## Unreleased as of Sprint 72 ending 2017-10-30

### Added
- Targeted refresh for pods using watches [(#135)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/135)
- Name custom attributes ICs nicely [(#128)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/128)
- Scanning job will read oscap erros from image-inspector [(#100)](https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/100)

## Initial changelog added
