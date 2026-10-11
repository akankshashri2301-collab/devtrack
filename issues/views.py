import json
import os

from django.conf import settings
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt

from .models import Reporter, Issue, CriticalIssue, LowPriorityIssue


def _path(name):
    return os.path.join(settings.BASE_DIR, name)


def _load(name):
    try:
        with open(_path(name), 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _save(name, data):
    with open(_path(name), 'w') as f:
        json.dump(data, f, indent=2)


def _parse_body(request):
    try:
        return json.loads(request.body), None
    except json.JSONDecodeError:
        return None, JsonResponse({'error': 'Invalid JSON body'}, status=400)


@csrf_exempt
def reporters(request):
    if request.method == 'POST':
        data, err = _parse_body(request)
        if err:
            return err
        try:
            reporter = Reporter(data['id'], data['name'], data['email'], data['team'])
            reporter.validate()
        except KeyError as e:
            return JsonResponse({'error': f'Missing field: {e.args[0]}'}, status=400)
        except ValueError as e:
            return JsonResponse({'error': str(e)}, status=400)

        all_reporters = _load('reporters.json')
        if any(r['id'] == reporter.id for r in all_reporters):
            return JsonResponse({'error': 'Reporter id already exists'}, status=400)

        all_reporters.append(reporter.to_dict())
        _save('reporters.json', all_reporters)
        return JsonResponse(reporter.to_dict(), status=201)

    if request.method == 'GET':
        all_reporters = _load('reporters.json')
        reporter_id = request.GET.get('id')
        if reporter_id is None:
            return JsonResponse(all_reporters, safe=False, status=200)
        try:
            reporter_id = int(reporter_id)
        except ValueError:
            return JsonResponse({'error': 'id must be an integer'}, status=400)
        for r in all_reporters:
            if r['id'] == reporter_id:
                return JsonResponse(r, status=200)
        return JsonResponse({'error': 'Reporter not found'}, status=404)

    return JsonResponse({'error': 'Method not allowed'}, status=405)


@csrf_exempt
def issues(request):
    if request.method == 'POST':
        data, err = _parse_body(request)
        if err:
            return err
        try:
            args = (data['id'], data['title'], data['description'],
                    data['status'], data['priority'], data['reporter_id'])
        except KeyError as e:
            return JsonResponse({'error': f'Missing field: {e.args[0]}'}, status=400)

        if data['priority'] == 'critical':
            issue = CriticalIssue(*args)
        elif data['priority'] == 'low':
            issue = LowPriorityIssue(*args)
        else:
            issue = Issue(*args)

        try:
            issue.validate()
        except ValueError as e:
            return JsonResponse({'error': str(e)}, status=400)

        all_issues = _load('issues.json')
        if any(i['id'] == issue.id for i in all_issues):
            return JsonResponse({'error': 'Issue id already exists'}, status=400)

        all_issues.append(issue.to_dict())
        _save('issues.json', all_issues)

        response_data = issue.to_dict()
        response_data['message'] = issue.describe()
        return JsonResponse(response_data, status=201)

    if request.method == 'GET':
        all_issues = _load('issues.json')
        issue_id = request.GET.get('id')
        status = request.GET.get('status')

        if issue_id is not None:
            try:
                issue_id = int(issue_id)
            except ValueError:
                return JsonResponse({'error': 'id must be an integer'}, status=400)
            for i in all_issues:
                if i['id'] == issue_id:
                    return JsonResponse(i, status=200)
            return JsonResponse({'error': 'Issue not found'}, status=404)

        if status is not None:
            filtered = [i for i in all_issues if i['status'] == status]
            return JsonResponse(filtered, safe=False, status=200)

        return JsonResponse(all_issues, safe=False, status=200)

    return JsonResponse({'error': 'Method not allowed'}, status=405)
