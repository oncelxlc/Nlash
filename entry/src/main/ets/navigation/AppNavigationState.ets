import { AppPage } from '../model/NavigationModels';

@Observed
export class AppNavigationState {
  selectedPage: AppPage = AppPage.DASHBOARD;

  selectPage(page: AppPage): void {
    this.selectedPage = page;
  }
}
